defmodule Credence.Rule.NoEnumTakeNegativeTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoEnumTakeNegative.check(ast, [])
  end

  defp fix(code) do
    Credence.Rule.NoEnumTakeNegative.fix(code, [])
  end

  describe "NoEnumTakeNegative check" do
    # --- POSITIVE CASES (should flag) ---

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
      assert issue.meta.line != nil
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

    # --- NEGATIVE CASES (should NOT flag) ---

    test "passes Enum.take with positive count" do
      code = """
      defmodule Good do
        def top_three(list) do
          Enum.sort(list, :desc) |> Enum.take(3)
        end
      end
      """

      assert check(code) == []
    end

    test "passes Enum.take with variable count" do
      code = """
      defmodule SafeVar do
        def take_n(list, n) do
          Enum.take(list, n)
        end
      end
      """

      assert check(code) == []
    end

    test "passes Enum.take with zero" do
      code = """
      defmodule Zero do
        def noop(list), do: Enum.take(list, 0)
      end
      """

      assert check(code) == []
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

    test "fixes piped list |> Enum.take(-3) to list |> Enum.slice" do
      code = """
      defmodule Example do
        def last_three(list) do
          list |> Enum.sort() |> Enum.take(-3)
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "Enum.take"
      assert fixed =~ "Enum.slice"
      assert fixed =~ "-3..-1//1"
      assert fixed =~ "|>"
    end

    test "fixes Enum.take(list, -5) with correct range" do
      code = """
      defmodule Example do
        def last_five(list) do
          Enum.take(list, -5)
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "Enum.take"
      assert fixed =~ "Enum.slice"
      assert fixed =~ "-5..-1//1"
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
      code = """
      defmodule Good do
        def first_three(list), do: Enum.take(list, 3)
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.take"
    end

    test "does not modify Enum.take with variable count" do
      code = """
      defmodule SafeVar do
        def take_n(list, n), do: Enum.take(list, n)
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.take"
    end

    test "fixes take at the end of a longer pipeline" do
      code = """
      defmodule Example do
        def process(data) do
          data
          |> Enum.sort()
          |> Enum.take(-3)
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "Enum.take"
      assert fixed =~ "Enum.slice"
      assert fixed =~ "-3..-1//1"
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
      issues = Credence.Rule.NoEnumTakeNegative.check(ast, [])
      assert issues == []
    end

    test "fixed piped code has no remaining issues" do
      code = """
      defmodule Example do
        def run(list) do
          list |> Enum.take(-2)
        end
      end
      """

      fixed = fix(code)
      {:ok, ast} = Code.string_to_quoted(fixed)
      issues = Credence.Rule.NoEnumTakeNegative.check(ast, [])
      assert issues == []
    end
  end
end
