defmodule Credence.Semantic.UsedUnderscoreVariableFixTest do
  use ExUnit.Case

  alias Credence.Semantic.UsedUnderscoreVariable

  defp diag(var_name, line, col \\ 1) do
    %{
      severity: :warning,
      message: ~s(the underscored variable "#{var_name}" is used after being set),
      position: {line, col}
    }
  end

  describe "fix/2 — guard on same line as parameter" do
    test "renames in both parameter and guard" do
      source = """
      defmodule M do
        defp build(_target_n, index) when index > _target_n, do: index
      end
      """

      expected = """
      defmodule M do
        defp build(target_n, index) when index > target_n, do: index
      end
      """

      assert UsedUnderscoreVariable.fix(source, diag("_target_n", 2)) == expected
    end

    test "does not rename other underscore variables" do
      source = """
      defmodule M do
        defp walk(_target_n, _index, acc, _last) when _index > _target_n, do: acc
      end
      """

      expected = """
      defmodule M do
        defp walk(target_n, _index, acc, _last) when _index > target_n, do: acc
      end
      """

      assert UsedUnderscoreVariable.fix(source, diag("_target_n", 2)) == expected
    end
  end

  describe "fix/2 — usage in body, declaration in function head" do
    test "fixes both declaration and body usage across lines" do
      source = """
      defmodule M do
        defp walk(target_n, current, _acc, _last) when current > target_n do
          Enum.reverse(_acc)
        end
      end
      """

      expected = """
      defmodule M do
        defp walk(target_n, current, acc, _last) when current > target_n do
          Enum.reverse(acc)
        end
      end
      """

      # Diagnostic points to line 3 (body usage of _acc)
      assert UsedUnderscoreVariable.fix(source, diag("_acc", 3)) == expected
    end

    test "fixes parameter and multiple body usages(and gap)" do
      source = """
      defmodule M do
        def process(_data, text) do
          cleaned = String.trim(text)
          String.upcase(_data) <> cleaned
        end
      end
      """

      expected = """
      defmodule M do
        def process(data, text) do
          cleaned = String.trim(text)
          String.upcase(data) <> cleaned
        end
      end
      """

      assert UsedUnderscoreVariable.fix(source, diag("_data", 3)) == expected
    end

    test "fixes parameter and multiple body usages" do
      source = """
      defmodule M do
        def process(_data) do
          cleaned = String.trim(_data)
          String.upcase(_data) <> cleaned
        end
      end
      """

      expected = """
      defmodule M do
        def process(data) do
          cleaned = String.trim(data)
          String.upcase(data) <> cleaned
        end
      end
      """

      assert UsedUnderscoreVariable.fix(source, diag("_data", 3)) == expected
    end
  end

  describe "fix/2 — clause isolation" do
    test "does not touch other function clauses" do
      source = """
      defmodule M do
        defp walk(_target_n, idx) when idx > _target_n, do: idx
        defp walk(_target_n, _idx), do: 0
      end
      """

      expected = """
      defmodule M do
        defp walk(target_n, idx) when idx > target_n, do: idx
        defp walk(_target_n, _idx), do: 0
      end
      """

      assert UsedUnderscoreVariable.fix(source, diag("_target_n", 2)) == expected
    end

    test "does not touch other function clauses (multi-line)" do
      source = """
      defmodule M do
        def run(_limit, value) do
          value + _limit
        end

        def run(_limit, _value) do
          0
        end
      end
      """

      expected = """
      defmodule M do
        def run(limit, value) do
          value + limit
        end

        def run(_limit, _value) do
          0
        end
      end
      """

      # Diagnostic points to line 3 (body usage in first clause)
      assert UsedUnderscoreVariable.fix(source, diag("_limit", 3)) == expected
    end
  end

  describe "fix/2 — word boundary safety" do
    test "does not partially match longer variable names" do
      source = """
      defmodule M do
        defp walk(_n, _num, idx) when idx > _n, do: idx
      end
      """

      expected = """
      defmodule M do
        defp walk(n, _num, idx) when idx > n, do: idx
      end
      """

      assert UsedUnderscoreVariable.fix(source, diag("_n", 2)) == expected
    end

    test "handles single-character underscore variable" do
      source = """
      defmodule M do
        def check(_x, y) when y > _x, do: :ok
      end
      """

      expected = """
      defmodule M do
        def check(x, y) when y > x, do: :ok
      end
      """

      assert UsedUnderscoreVariable.fix(source, diag("_x", 2)) == expected
    end
  end

  describe "fix/2 — position formats" do
    test "handles bare integer position" do
      source = "def check(_x, y) when y > _x, do: :ok\n"
      expected = "def check(x, y) when y > x, do: :ok\n"

      bare_diag = %{
        severity: :warning,
        message: ~s(variable "_x" is used after being set),
        position: 1
      }

      assert UsedUnderscoreVariable.fix(source, bare_diag) == expected
    end
  end

  describe "fix/2 — no-ops" do
    test "returns source unchanged when variable has no underscore" do
      source = "def check(x, y) when y > x, do: :ok\n"

      weird_diag = %{
        severity: :warning,
        message: ~s(variable "x" is used after being set),
        position: {1, 1}
      }

      assert UsedUnderscoreVariable.fix(source, weird_diag) == source
    end

    test "returns source unchanged when position is nil" do
      source = "some code\n"

      bad_diag = %{
        severity: :warning,
        message: ~s(variable "_x" is used after being set),
        position: nil
      }

      assert UsedUnderscoreVariable.fix(source, bad_diag) == source
    end

    test "returns source unchanged when message has no variable name" do
      source = "some code\n"

      bad_diag = %{
        severity: :warning,
        message: "something is used after being set",
        position: {1, 1}
      }

      assert UsedUnderscoreVariable.fix(source, bad_diag) == source
    end
  end

  describe "integration through Credence.Semantic" do
    test "fixes underscore variable in guard end-to-end" do
      source = """
      defmodule UsedUnderscoreFixInteg1 do
        def check(_limit, value) when value > _limit, do: :over
      end
      """

      expected = """
      defmodule UsedUnderscoreFixInteg1 do
        def check(limit, value) when value > limit, do: :over
      end
      """

      fixed = Credence.Semantic.fix(source)
      assert fixed == expected
    end

    test "fixes underscore variable used in body end-to-end" do
      source = """
      defmodule UsedUnderscoreFixInteg2 do
        def check(_limit, value) do
          value + _limit
        end
      end
      """

      expected = """
      defmodule UsedUnderscoreFixInteg2 do
        def check(limit, value) do
          value + limit
        end
      end
      """

      fixed = Credence.Semantic.fix(source)
      assert fixed == expected
    end

    test "does not modify correctly unused underscore variable" do
      source = """
      defmodule UsedUnderscoreFixInteg3 do
        def check(_limit, value), do: value
      end
      """

      fixed = Credence.Semantic.fix(source)
      assert fixed == source
    end
  end
end
