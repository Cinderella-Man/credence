defmodule Credence.Pattern.NoRedundantDedupBeforeMapsetTest do
  use ExUnit.Case

  alias Credence.Pattern.NoRedundantDedupBeforeMapset

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoRedundantDedupBeforeMapset.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoRedundantDedupBeforeMapset, code, [])
  end

  describe "check/2" do
    test "fires on Enum.dedup(x) |> MapSet.new()" do
      code = """
      defmodule Example do
        def run(items) do
          Enum.dedup(items) |> MapSet.new()
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_redundant_dedup_before_mapset
    end

    test "fires on x |> Enum.dedup() |> MapSet.new()" do
      code = """
      defmodule Example do
        def run(items) do
          items |> Enum.dedup() |> MapSet.new()
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "fires on MapSet.new(Enum.dedup(x))" do
      code = """
      defmodule Example do
        def run(items) do
          MapSet.new(Enum.dedup(items))
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "fires on Enum.uniq(x) |> MapSet.new()" do
      code = """
      defmodule Example do
        def run(items) do
          Enum.uniq(items) |> MapSet.new()
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "fires on MapSet.new(Enum.uniq(x))" do
      code = """
      defmodule Example do
        def run(items) do
          MapSet.new(Enum.uniq(items))
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "fires on multiple occurrences in same module" do
      code = """
      defmodule Example do
        def run(a, b) do
          first = Enum.dedup(a) |> MapSet.new()
          second = Enum.dedup(b) |> MapSet.new()
          {first, second}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end

    test "does not fire on MapSet.new(items)" do
      code = """
      defmodule Example do
        def run(items) do
          MapSet.new(items)
        end
      end
      """

      assert check(code) == []
    end

    test "does not fire on Enum.dedup used alone" do
      code = """
      defmodule Example do
        def run(items) do
          Enum.dedup(items)
        end
      end
      """

      assert check(code) == []
    end

    test "does not fire on Enum.dedup piped to non-MapSet function" do
      code = """
      defmodule Example do
        def run(items) do
          Enum.dedup(items) |> Enum.count()
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix/2" do
    test "fixes Enum.dedup(x) |> MapSet.new() to MapSet.new(x)" do
      code = "Enum.dedup(items) |> MapSet.new()"
      result = fix(code)
      assert result =~ "MapSet.new(items)"
      refute result =~ "Enum.dedup"
    end

    test "fixes MapSet.new(Enum.dedup(x)) to MapSet.new(x)" do
      code = "MapSet.new(Enum.dedup(items))"
      result = fix(code)
      assert result =~ "MapSet.new(items)"
      refute result =~ "Enum.dedup"
    end

    test "fixes Enum.uniq(x) |> MapSet.new() to MapSet.new(x)" do
      code = "Enum.uniq(items) |> MapSet.new()"
      result = fix(code)
      assert result =~ "MapSet.new(items)"
      refute result =~ "Enum.uniq"
    end

    test "preserves surrounding code" do
      code = """
      defmodule Solution do
        def run(first_list, second_list) do
          first_set = Enum.dedup(first_list) |> MapSet.new()
          second_set = Enum.dedup(second_list) |> MapSet.new()
          {first_set, second_set}
        end
      end
      """

      result = fix(code)
      assert result =~ "MapSet.new(first_list)"
      assert result =~ "MapSet.new(second_list)"
      assert result =~ "{first_set, second_set}"
    end

    test "fixed code produces no issues" do
      code = """
      defmodule RoundTrip do
        def run(items) do
          Enum.dedup(items) |> MapSet.new()
        end
      end
      """

      fixed = fix(code)
      {:ok, fixed_ast} = Sourceror.parse_string(fixed)
      issues = NoRedundantDedupBeforeMapset.check(fixed_ast, [])
      assert issues == []
    end
  end
end
