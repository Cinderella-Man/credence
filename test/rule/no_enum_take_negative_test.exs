defmodule Credence.Pattern.NoEnumTakeNegativeTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoEnumTakeNegative.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoEnumTakeNegative.fix(code, [])
  end

  describe "NoEnumTakeNegative check" do
    test "detects Enum.take with negative literal" do
      code = """
      defmodule BadTake do
        def last_three(list) do
          sorted = Enum.sort(list)
          Enum.take(sorted, -3)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_enum_take_negative
      assert issue.message =~ "-3"
    end

    test "detects piped Enum.take with negative literal" do
      code = """
      defmodule BadPiped do
        def last_three(list) do
          list |> Enum.sort() |> Enum.take(-3)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_enum_take_negative
    end

    test "detects Enum.take(-1)" do
      code = """
      defmodule BadOne do
        def last(list), do: Enum.take(list, -1)
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).message =~ "-1"
    end

    test "passes Enum.take with positive count" do
      assert check("defmodule G do\n  def f(l), do: Enum.sort(l, :desc) |> Enum.take(3)\nend") ==
               []
    end

    test "passes Enum.take with variable count" do
      assert check("defmodule G do\n  def f(l, n), do: Enum.take(l, n)\nend") == []
    end

    test "passes Enum.take with zero" do
      assert check("defmodule G do\n  def f(l), do: Enum.take(l, 0)\nend") == []
    end
  end

  describe "NoEnumTakeNegative fix" do
    test "fixes direct Enum.take(list, -1) to Enum.slice" do
      code = """
      defmodule Example do
        def last(list) do
          Enum.take(list, -1)
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "Enum.take"
      assert fixed =~ "Enum.slice"
      assert fixed =~ "-1..-1//1"
    end

    test "fixes direct Enum.take(list, -3) to Enum.slice" do
      code = """
      defmodule Example do
        def last_three(list) do
          Enum.take(list, -3)
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "Enum.take"
      assert fixed =~ "Enum.slice"
      assert fixed =~ "-3..-1//1"
    end

    test "fixes piped take after non-sort step" do
      code = """
      defmodule Example do
        def last_three(list) do
          list |> Enum.filter(&(&1 > 0)) |> Enum.take(-3)
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "Enum.take"
      assert fixed =~ "Enum.slice"
      assert fixed =~ "-3..-1//1"
    end

    test "fixes multiple negative takes in one file" do
      code = """
      defmodule Example do
        def process(list) do
          a = Enum.take(list, -1)
          b = Enum.take(list, -3)
          {a, b}
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "Enum.take"
      assert fixed =~ "-1..-1//1"
      assert fixed =~ "-3..-1//1"
    end

    test "does not modify Enum.take with positive count" do
      fixed = fix("defmodule G do\n  def f(l), do: Enum.take(l, 3)\nend\n")
      assert fixed =~ "Enum.take"
    end

    test "does not modify Enum.take with variable count" do
      fixed = fix("defmodule G do\n  def f(l, n), do: Enum.take(l, n)\nend\n")
      assert fixed =~ "Enum.take"
    end

    test "fixes direct call with complex first argument" do
      code = """
      defmodule Example do
        def process(map) do
          Enum.take(Map.values(map), -2)
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "Enum.take"
      assert fixed =~ "Enum.slice"
      assert fixed =~ "-2..-1//1"
    end

    test "fixed code has no remaining issues" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.take(list, -3)
        end
      end
      """

      fixed = fix(code)
      {:ok, ast} = Code.string_to_quoted(fixed)
      assert Credence.Pattern.NoEnumTakeNegative.check(ast, []) == []
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

      fixed = fix(code)
      # Not converted to slice — left for PreferDescSortOverNegativeTake
      assert fixed =~ "Enum.take"
      refute fixed =~ "Enum.slice"
    end

    test "defers Enum.sort(list) |> take(-n) to PreferDescSortOverNegativeTake (direct)" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.sort(list) |> Enum.take(-3)
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.take"
      refute fixed =~ "Enum.slice"
    end

    test "does NOT defer when sort has comparator" do
      code = """
      defmodule Example do
        def run(list) do
          list |> Enum.sort(&>=/2) |> Enum.take(-3)
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "Enum.take"
      assert fixed =~ "Enum.slice"
    end
  end
end
