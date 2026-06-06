defmodule Credence.Pattern.PreferEnumSplitFixTest do
  use ExUnit.Case

  alias Credence.Pattern.PreferEnumSplit

  defp fix(code) do
    result = Credence.RuleHelpers.apply_rule_fix(PreferEnumSplit, code, [])
    if String.ends_with?(result, "\n"), do: result, else: result <> "\n"
  end

  describe "collapse to Enum.split/2" do
    test "adjacent take/drop with a literal count" do
      code = """
      defmodule Bad do
        def halves(list) do
          first = Enum.take(list, 3)
          rest = Enum.drop(list, 3)
          {first, rest}
        end
      end
      """

      expected = """
      defmodule Bad do
        def halves(list) do
          {first, rest} = Enum.split(list, 3)
          {first, rest}
        end
      end
      """

      assert fix(code) == expected
    end

    test "literal count of zero" do
      code = """
      defmodule Bad do
        def halves(list) do
          a = Enum.take(list, 0)
          b = Enum.drop(list, 0)
          {a, b}
        end
      end
      """

      expected = """
      defmodule Bad do
        def halves(list) do
          {a, b} = Enum.split(list, 0)
          {a, b}
        end
      end
      """

      assert fix(code) == expected
    end

    test "drop's bound var equals the source var" do
      code = """
      defmodule Bad do
        def halves(list) do
          first = Enum.take(list, 3)
          list = Enum.drop(list, 3)
          {first, list}
        end
      end
      """

      expected = """
      defmodule Bad do
        def halves(list) do
          {first, list} = Enum.split(list, 3)
          {first, list}
        end
      end
      """

      assert fix(code) == expected
    end
  end

  describe "leaves dropped/unrelated cases untouched" do
    test "variable count is untouched" do
      code = """
      defmodule VarCount do
        def halves(list, n) do
          first = Enum.take(list, n)
          rest = Enum.drop(list, n)
          {first, rest}
        end
      end
      """

      assert fix(code) == code
    end

    test "negative literal count is untouched" do
      code = """
      defmodule NegCount do
        def halves(list) do
          first = Enum.take(list, -3)
          rest = Enum.drop(list, -3)
          {first, rest}
        end
      end
      """

      assert fix(code) == code
    end

    test "reverse-wrapped drop is untouched" do
      code = """
      defmodule ReverseWrapped do
        def split_halves(sorted) do
          first_half = Enum.take(sorted, 3)
          last_half = Enum.reverse(Enum.drop(sorted, 3))
          {first_half, last_half}
        end
      end
      """

      assert fix(code) == code
    end

    test "piped take/drop is untouched" do
      code = """
      defmodule Piped do
        def halves(list) do
          first = list |> Enum.take(3)
          rest = list |> Enum.drop(3)
          {first, rest}
        end
      end
      """

      assert fix(code) == code
    end

    test "non-adjacent take/drop is untouched" do
      code = """
      defmodule NonAdjacent do
        def halves(list) do
          first = Enum.take(list, 3)
          mid = process(first)
          rest = Enum.drop(list, 3)
          {first, mid, rest}
        end
      end
      """

      assert fix(code) == code
    end

    test "take rebinding the source is untouched" do
      code = """
      defmodule Rebind do
        def halves(list) do
          list = Enum.take(list, 3)
          rest = Enum.drop(list, 3)
          {list, rest}
        end
      end
      """

      assert fix(code) == code
    end

    test "already uses Enum.split" do
      code = """
      defmodule Good do
        def halves(list) do
          {first, rest} = Enum.split(list, 3)
          {first, rest}
        end
      end
      """

      assert fix(code) == code
    end
  end
end
