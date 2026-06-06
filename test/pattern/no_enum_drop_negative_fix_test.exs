defmodule Credence.Pattern.NoEnumDropNegativeFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoEnumDropNegative

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoEnumDropNegative.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoEnumDropNegative, code, [])
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  describe "NoEnumDropNegative fix" do
    test "fixes direct Enum.drop(list, -1) to Enum.slice" do
      input = """
      defmodule Example do
        def remove_last(list) do
          Enum.drop(list, -1)
        end
      end
      """

      expected = """
      defmodule Example do
        def remove_last(list) do
          Enum.slice(list, 0..-2//1)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes piped list |> Enum.drop(-1) to list |> Enum.slice" do
      input = """
      defmodule Example do
        def remove_last(list) do
          list |> Enum.drop(-1)
        end
      end
      """

      expected = """
      defmodule Example do
        def remove_last(list) do
          list |> Enum.slice(0..-2//1)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes Enum.drop(list, -2) with correct range end" do
      input = """
      defmodule Example do
        def remove_last_two(list) do
          Enum.drop(list, -2)
        end
      end
      """

      expected = """
      defmodule Example do
        def remove_last_two(list) do
          Enum.slice(list, 0..-3//1)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes Enum.drop(list, -5) with correct range end" do
      input = """
      defmodule Example do
        def remove_last_five(list) do
          Enum.drop(list, -5)
        end
      end
      """

      expected = """
      defmodule Example do
        def remove_last_five(list) do
          Enum.slice(list, 0..-6//1)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes piped Enum.drop(-3) with correct range end" do
      input = """
      defmodule Example do
        def trim(list) do
          list |> Enum.drop(-3)
        end
      end
      """

      expected = """
      defmodule Example do
        def trim(list) do
          list |> Enum.slice(0..-4//1)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes multiple negative drops in one file" do
      input = """
      defmodule Example do
        def process(list) do
          a = Enum.drop(list, -1)
          b = Enum.drop(list, -2)
          {a, b}
        end
      end
      """

      expected = """
      defmodule Example do
        def process(list) do
          a = Enum.slice(list, 0..-2//1)
          b = Enum.slice(list, 0..-3//1)
          {a, b}
        end
      end
      """

      assert fix(input) == expected
    end

    test "does not modify Enum.drop with positive count" do
      code = """
      defmodule Good do
        def skip_first(list), do: Enum.drop(list, 1)
      end
      """

      assert fix(code) == code
    end

    test "does not modify Enum.drop with variable count" do
      code = """
      defmodule SafeVar do
        def drop_n(list, n), do: Enum.drop(list, n)
      end
      """

      assert fix(code) == code
    end

    test "fixes drop at the end of a longer pipeline" do
      input = """
      defmodule Example do
        def process(data) do
          data
          |> Enum.map(&String.trim/1)
          |> Enum.filter(&(&1 != ""))
          |> Enum.drop(-1)
        end
      end
      """

      expected = """
      defmodule Example do
        def process(data) do
          data
          |> Enum.map(&String.trim/1)
          |> Enum.filter(&(&1 != ""))
          |> Enum.slice(0..-2//1)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes direct call with complex first argument" do
      input = """
      defmodule Example do
        def process(map) do
          Enum.drop(Map.values(map), -1)
        end
      end
      """

      expected = """
      defmodule Example do
        def process(map) do
          Enum.slice(Map.values(map), 0..-2//1)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixed code has no remaining issues" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.drop(list, -1)
        end
      end
      """

      assert check(fix(code)) == []
    end

    test "fixed piped code has no remaining issues" do
      code = """
      defmodule Example do
        def run(list) do
          list |> Enum.drop(-2)
        end
      end
      """

      assert check(fix(code)) == []
    end
  end
end
