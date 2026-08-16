defmodule Credence.Semantic.UsedUnderscoreVariableFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

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

      confirm_fix(UsedUnderscoreVariable.fix(source, diag("_target_n", 2)), expected)
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

      confirm_fix(UsedUnderscoreVariable.fix(source, diag("_target_n", 2)), expected)
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
      confirm_fix(UsedUnderscoreVariable.fix(source, diag("_acc", 3)), expected)
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

      confirm_fix(UsedUnderscoreVariable.fix(source, diag("_data", 3)), expected)
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

      confirm_fix(UsedUnderscoreVariable.fix(source, diag("_data", 3)), expected)
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

      confirm_fix(UsedUnderscoreVariable.fix(source, diag("_target_n", 2)), expected)
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
      confirm_fix(UsedUnderscoreVariable.fix(source, diag("_limit", 3)), expected)
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

      confirm_fix(UsedUnderscoreVariable.fix(source, diag("_n", 2)), expected)
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

      confirm_fix(UsedUnderscoreVariable.fix(source, diag("_x", 2)), expected)
    end
  end

  describe "fix/2 — position formats" do
    test "handles bare integer position" do
      source = "def check(_x, y) when y > _x, do: :ok"

      expected = "def check(x, y) when y > x, do: :ok"

      bare_diag = %{
        severity: :warning,
        message: """
        variable "_x" is used after being set
        """,
        position: 1
      }

      confirm_fix(UsedUnderscoreVariable.fix(source, bare_diag), expected)
    end
  end

  describe "fix/2 — no-ops" do
    test "returns source unchanged when variable has no underscore" do
      source = "def check(x, y) when y > x, do: :ok"

      weird_diag = %{
        severity: :warning,
        message: """
        variable "x" is used after being set
        """,
        position: {1, 1}
      }

      confirm_fix(UsedUnderscoreVariable.fix(source, weird_diag), source)
    end

    test "returns source unchanged when position is nil" do
      source = "some code"

      bad_diag = %{
        severity: :warning,
        message: """
        variable "_x" is used after being set
        """,
        position: nil
      }

      confirm_fix(UsedUnderscoreVariable.fix(source, bad_diag), source)
    end

    test "returns source unchanged when message has no variable name" do
      source = "some code"

      bad_diag = %{
        severity: :warning,
        message: "something is used after being set",
        position: {1, 1}
      }

      confirm_fix(UsedUnderscoreVariable.fix(source, bad_diag), source)
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
      confirm_fix(fixed, expected)
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
      confirm_fix(fixed, expected)
    end

    test "does not modify correctly unused underscore variable" do
      source = """
      defmodule UsedUnderscoreFixInteg3 do
        def check(_limit, value), do: value
      end
      """

      fixed = Credence.Semantic.fix(source)
      confirm_fix(fixed, source)
    end
  end

  describe "fix output is well-formed" do
    test "fixed output parses" do
      source = """
      defmodule M do
        defp build(_target_n, index) when index > _target_n, do: index
      end
      """

      assert valid_syntax?(UsedUnderscoreVariable.fix(source, diag("_target_n", 2)))
    end
  end

  # ── T3.12: the stripped name must still BE a variable ──────────────────
  #
  # Found by the T2.5 idempotency sweep, which ran `Credence.fix/1` twice over
  # all 5,184 fix-test fixtures: `__MODULE` walked one underscore per pass to
  # `_MODULE` and then to `MODULE`. `MODULE` is an alias, so `MODULE = :mod`
  # compiles clean and raises MatchError at RUNTIME — the "output compiles but
  # means something else" class, the worst shape a fix can have.
  describe "names that would stop being variables" do
    test "declines when stripping would produce an alias" do
      source = """
      defmodule M do
        def ok do
          _MODULE = :mod
          IO.inspect(_MODULE)
        end
      end
      """

      confirm_fix(UsedUnderscoreVariable.fix(source, diag("_MODULE", 3)), source)
    end

    test "strips every leading underscore in one pass, not one per pass" do
      source = """
      defmodule M do
        def ok do
          __foo = :mod
          IO.inspect(__foo)
        end
      end
      """

      fixed = UsedUnderscoreVariable.fix(source, diag("__foo", 3))

      assert fixed =~ "foo = :mod"
      refute fixed =~ "_foo"
      # Idempotent: the whole point. One pass reaches the fixpoint.
      confirm_fix(UsedUnderscoreVariable.fix(fixed, diag("foo", 3)), fixed)
    end

    test "declines a double-underscored alias rather than walking toward one" do
      source = """
      defmodule M do
        def ok do
          __MODULE = :mod
          IO.inspect(__MODULE)
        end
      end
      """

      confirm_fix(UsedUnderscoreVariable.fix(source, diag("__MODULE", 3)), source)
    end

    test "declines a bare underscore rather than splicing an empty name" do
      source = """
      defmodule M do
        def ok do
          _ = :mod
          IO.inspect(_)
        end
      end
      """

      confirm_fix(UsedUnderscoreVariable.fix(source, diag("_", 3)), source)
    end

    test "GREEN-0: the ordinary single-underscore rename still works" do
      source = """
      defmodule M do
        defp build(_target_n, index) when index > _target_n, do: index
      end
      """

      fixed = UsedUnderscoreVariable.fix(source, diag("_target_n", 2))

      assert fixed =~ "target_n"
      refute fixed =~ "_target_n"
    end
  end

  # ── Byte scope: a mention in a comment or a string is not code. ──
  #
  # Found by planting a decoy rather than by reading: the rename ran a plain
  # `Regex.replace` over every raw line in the clause, so `_limit` in a trailing
  # comment was renamed along with the parameter. Same class as
  # `UndefinedFunction` (docs/22 T3.7, T3.10); the repair is `SourceMask`.

  describe "byte scope" do
    test "a mention of the variable in a trailing comment is left alone" do
      source = """
      defmodule UuvComment do
        def check(_limit, value) do  # def check(_limit, value) do
          _limit + value
        end
      end
      """

      fixed = UsedUnderscoreVariable.fix(source, diag("_limit", 2))

      assert fixed =~ "def check(limit, value) do"
      assert fixed =~ "# def check(_limit, value) do"
      assert fixed =~ "limit + value"
    end

    test "a mention inside a string literal is left alone" do
      source = """
      defmodule UuvString do
        def check(_limit, value) do
          IO.puts("_limit is the cap")
          _limit + value
        end
      end
      """

      fixed = UsedUnderscoreVariable.fix(source, diag("_limit", 2))

      assert fixed =~ ~s|IO.puts("_limit is the cap")|
      assert fixed =~ "limit + value"
    end

    # The control: masking must not blind the rename to ordinary code. Two real
    # usages on one line still both rename.
    test "CONTROL: two code usages on one line both rename" do
      source = """
      defmodule UuvTwice do
        def check(_limit, value) do
          _limit + _limit + value
        end
      end
      """

      assert UsedUnderscoreVariable.fix(source, diag("_limit", 2)) =~ "limit + limit + value"
    end
  end
end
