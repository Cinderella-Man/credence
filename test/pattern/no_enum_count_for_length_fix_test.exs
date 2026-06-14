defmodule Credence.Pattern.NoEnumCountForLengthFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoEnumCountForLength

  describe "rewrites Enum.count/1 over a known list to length/1" do
    test "in a pipeline" do
      input = """
      defmodule Bad do
        def count_items(list) do
          list
          |> Enum.filter(&(&1 > 0))
          |> Enum.count()
        end
      end
      """

      expected = """
      defmodule Bad do
        def count_items(list) do
          list
          |> Enum.filter(&(&1 > 0))
          |> length()
        end
      end
      """

      confirm_fix(fix(NoEnumCountForLength, input), expected)
    end

    test "with a direct expression" do
      input = """
      defmodule Bad do
        def grapheme_count(str) do
          Enum.count(String.graphemes(str))
        end
      end
      """

      expected = """
      defmodule Bad do
        def grapheme_count(str) do
          length(String.graphemes(str))
        end
      end
      """

      confirm_fix(fix(NoEnumCountForLength, input), expected)
    end

    test "multiple calls, independently" do
      input = """
      defmodule Bad do
        def compare(a, b) do
          Enum.count(String.graphemes(a)) == Enum.count(String.graphemes(b))
        end
      end
      """

      expected = """
      defmodule Bad do
        def compare(a, b) do
          length(String.graphemes(a)) == length(String.graphemes(b))
        end
      end
      """

      confirm_fix(fix(NoEnumCountForLength, input), expected)
    end

    test "in an assignment, leaving surrounding code intact" do
      input = """
      defmodule Bad do
        def process(items) do
          n = Enum.count(String.graphemes(items))
          Enum.reduce(0..(n - 1), 0, fn i, acc -> acc + i end)
        end
      end
      """

      expected = """
      defmodule Bad do
        def process(items) do
          n = length(String.graphemes(items))
          Enum.reduce(0..(n - 1), 0, fn i, acc -> acc + i end)
        end
      end
      """

      confirm_fix(fix(NoEnumCountForLength, input), expected)
    end
  end

  describe "leaves untouched" do
    test "Enum.count/2 with a predicate" do
      code = """
      defmodule Good do
        def count_positives(list) do
          Enum.count(list, &(&1 > 0))
        end
      end
      """

      confirm_fix(fix(NoEnumCountForLength, code), code)
    end

    test "length/1 (already correct)" do
      code = """
      defmodule Good do
        def size(list), do: length(list)
      end
      """

      confirm_fix(fix(NoEnumCountForLength, code), code)
    end

    test "Enum.count on a bare variable" do
      code = """
      defmodule Good do
        def process(input) do
          chars = String.graphemes(input)
          total = Enum.count(chars)
          {chars, total}
        end
      end
      """

      confirm_fix(fix(NoEnumCountForLength, code), code)
    end
  end
end
