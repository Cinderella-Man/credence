defmodule Credence.Pattern.NoEnumTakeNegativeFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoEnumTakeNegative

  describe "NoEnumTakeNegative fix" do
    test "fixes direct Enum.take(list, -1) to Enum.slice" do
      input = """
      defmodule Example do
        def last(list) do
          Enum.take(list, -1)
        end
      end
      """

      expected = """
      defmodule Example do
        def last(list) do
          Enum.slice(list, -1..-1//1)
        end
      end
      """

      confirm_fix(fix(NoEnumTakeNegative, input), expected)
    end

    test "fixes direct Enum.take(list, -3) to Enum.slice" do
      input = """
      defmodule Example do
        def last_three(list) do
          Enum.take(list, -3)
        end
      end
      """

      expected = """
      defmodule Example do
        def last_three(list) do
          Enum.slice(list, -3..-1//1)
        end
      end
      """

      confirm_fix(fix(NoEnumTakeNegative, input), expected)
    end

    test "fixes piped take after non-sort step" do
      input = """
      defmodule Example do
        def last_three(list) do
          list |> Enum.filter(&(&1 > 0)) |> Enum.take(-3)
        end
      end
      """

      expected = """
      defmodule Example do
        def last_three(list) do
          list |> Enum.filter(&(&1 > 0)) |> Enum.slice(-3..-1//1)
        end
      end
      """

      confirm_fix(fix(NoEnumTakeNegative, input), expected)
    end

    test "fixes multiple negative takes in one file" do
      input = """
      defmodule Example do
        def process(list) do
          a = Enum.take(list, -1)
          b = Enum.take(list, -3)
          {a, b}
        end
      end
      """

      expected = """
      defmodule Example do
        def process(list) do
          a = Enum.slice(list, -1..-1//1)
          b = Enum.slice(list, -3..-1//1)
          {a, b}
        end
      end
      """

      confirm_fix(fix(NoEnumTakeNegative, input), expected)
    end

    test "does not modify Enum.take with positive count" do
      code = """
      defmodule G do
        def f(l), do: Enum.take(l, 3)
      end
      """

      confirm_fix(fix(NoEnumTakeNegative, code), code)
    end

    test "does not modify Enum.take with variable count" do
      code = """
      defmodule G do
        def f(l, n), do: Enum.take(l, n)
      end
      """

      confirm_fix(fix(NoEnumTakeNegative, code), code)
    end

    test "fixes direct call with complex first argument" do
      input = """
      defmodule Example do
        def process(map) do
          Enum.take(Map.values(map), -2)
        end
      end
      """

      expected = """
      defmodule Example do
        def process(map) do
          Enum.slice(Map.values(map), -2..-1//1)
        end
      end
      """

      confirm_fix(fix(NoEnumTakeNegative, input), expected)
    end

    test "fixed code has no remaining issues" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.take(list, -3)
        end
      end
      """

      assert check(NoEnumTakeNegative, fix(NoEnumTakeNegative, code)) == []
    end

    # ── Skip behavior: sort |> take(-n) deferred ──────────────────

    test "defers sort() |> take(-n) to PreferDescSortOverNegativeTake (piped)" do
      code = """
      defmodule Example do
        def run(list) do
          list |> Enum.sort() |> Enum.take(-3)
        end
      end
      """

      # Not converted to slice — left for PreferDescSortOverNegativeTake.
      confirm_fix(fix(NoEnumTakeNegative, code), code)
    end

    test "defers Enum.sort(list) |> take(-n) to PreferDescSortOverNegativeTake (direct)" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.sort(list) |> Enum.take(-3)
        end
      end
      """

      confirm_fix(fix(NoEnumTakeNegative, code), code)
    end

    test "does NOT defer when sort has comparator" do
      input = """
      defmodule Example do
        def run(list) do
          list |> Enum.sort(&>=/2) |> Enum.take(-3)
        end
      end
      """

      expected = """
      defmodule Example do
        def run(list) do
          list |> Enum.sort(&>=/2) |> Enum.slice(-3..-1//1)
        end
      end
      """

      confirm_fix(fix(NoEnumTakeNegative, input), expected)
    end
  end
end
