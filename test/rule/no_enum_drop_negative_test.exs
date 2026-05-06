defmodule Credence.Pattern.NoEnumDropNegativeTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoEnumDropNegative.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoEnumDropNegative.fix(code, [])
  end

  describe "NoEnumDropNegative check" do
    # --- POSITIVE CASES (should flag) ---

    test "detects Enum.drop with negative literal" do
      code = """
      defmodule BadDrop do
        def remove_last(list) do
          Enum.drop(list, -1)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_enum_drop_negative
      assert issue.message =~ "-1"
      assert issue.meta.line != nil
    end

    test "detects piped Enum.drop with negative literal" do
      code = """
      defmodule BadPiped do
        def remove_last(list) do
          list |> Enum.drop(-1)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_enum_drop_negative
    end

    test "detects multiple negative drops" do
      code = """
      defmodule MultipleBad do
        def process(list) do
          a = Enum.drop(list, -1)
          b = Enum.drop(list, -2)
          {a, b}
        end
      end
      """

      issues = check(code)

      assert length(issues) == 2
    end

    # --- NEGATIVE CASES (should NOT flag) ---

    test "passes Enum.drop with positive count" do
      code = """
      defmodule Good do
        def skip_first(list), do: Enum.drop(list, 1)
      end
      """

      assert check(code) == []
    end

    test "passes Enum.drop with variable count" do
      code = """
      defmodule SafeVar do
        def drop_n(list, n), do: Enum.drop(list, n)
      end
      """

      assert check(code) == []
    end

    test "passes Enum.drop with zero" do
      code = """
      defmodule Zero do
        def noop(list), do: Enum.drop(list, 0)
      end
      """

      assert check(code) == []
    end
  end

  describe "NoEnumDropNegative fix" do
    test "fixes direct Enum.drop(list, -1) to Enum.slice" do
      code = """
      defmodule Example do
        def remove_last(list) do
          Enum.drop(list, -1)
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "Enum.drop"
      assert fixed =~ "Enum.slice"
      assert fixed =~ "0..-2//1"
    end

    test "fixes piped list |> Enum.drop(-1) to list |> Enum.slice" do
      code = """
      defmodule Example do
        def remove_last(list) do
          list |> Enum.drop(-1)
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "Enum.drop"
      assert fixed =~ "Enum.slice"
      assert fixed =~ "0..-2//1"
      assert fixed =~ "|>"
    end

    test "fixes Enum.drop(list, -2) with correct range end" do
      code = """
      defmodule Example do
        def remove_last_two(list) do
          Enum.drop(list, -2)
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "Enum.drop"
      assert fixed =~ "Enum.slice"
      assert fixed =~ "0..-3//1"
    end

    test "fixes Enum.drop(list, -5) with correct range end" do
      code = """
      defmodule Example do
        def remove_last_five(list) do
          Enum.drop(list, -5)
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "Enum.drop"
      assert fixed =~ "Enum.slice"
      assert fixed =~ "0..-6//1"
    end

    test "fixes piped Enum.drop(-3) with correct range end" do
      code = """
      defmodule Example do
        def trim(list) do
          list |> Enum.drop(-3)
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "Enum.drop"
      assert fixed =~ "Enum.slice"
      assert fixed =~ "0..-4//1"
    end

    test "fixes multiple negative drops in one file" do
      code = """
      defmodule Example do
        def process(list) do
          a = Enum.drop(list, -1)
          b = Enum.drop(list, -2)
          {a, b}
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "Enum.drop"
      assert fixed =~ "0..-2//1"
      assert fixed =~ "0..-3//1"
    end

    test "does not modify Enum.drop with positive count" do
      code = """
      defmodule Good do
        def skip_first(list), do: Enum.drop(list, 1)
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.drop"
    end

    test "does not modify Enum.drop with variable count" do
      code = """
      defmodule SafeVar do
        def drop_n(list, n), do: Enum.drop(list, n)
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.drop"
    end

    test "fixes drop at the end of a longer pipeline" do
      code = """
      defmodule Example do
        def process(data) do
          data
          |> Enum.map(&String.trim/1)
          |> Enum.filter(&(&1 != ""))
          |> Enum.drop(-1)
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "Enum.drop"
      assert fixed =~ "Enum.slice"
      assert fixed =~ "0..-2//1"
    end

    test "fixes direct call with complex first argument" do
      code = """
      defmodule Example do
        def process(map) do
          Enum.drop(Map.values(map), -1)
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "Enum.drop"
      assert fixed =~ "Enum.slice"
      assert fixed =~ "0..-2//1"
    end

    test "fixed code has no remaining issues" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.drop(list, -1)
        end
      end
      """

      fixed = fix(code)
      {:ok, ast} = Code.string_to_quoted(fixed)
      issues = Credence.Pattern.NoEnumDropNegative.check(ast, [])
      assert issues == []
    end

    test "fixed piped code has no remaining issues" do
      code = """
      defmodule Example do
        def run(list) do
          list |> Enum.drop(-2)
        end
      end
      """

      fixed = fix(code)
      {:ok, ast} = Code.string_to_quoted(fixed)
      issues = Credence.Pattern.NoEnumDropNegative.check(ast, [])
      assert issues == []
    end
  end
end
