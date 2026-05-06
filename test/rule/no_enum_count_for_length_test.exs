defmodule Credence.Pattern.NoEnumCountForLengthTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoEnumCountForLength.check(ast, [])
  end

  describe "NoEnumCountForLength" do
    test "detects Enum.count(var) on a list variable" do
      code = """
      defmodule Bad do
        def process(input) do
          chars = String.graphemes(input)
          total = Enum.count(chars)
          {chars, total}
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_enum_count_for_length

      assert issue.message =~ "length/1"
    end

    test "detects Enum.count in a pipeline" do
      code = """
      defmodule Bad do
        def count_items(list) do
          list
          |> Enum.filter(&(&1 > 0))
          |> Enum.count()
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.count/1"
    end

    test "detects Enum.count with a direct expression" do
      code = """
      defmodule Bad do
        def grapheme_count(str) do
          Enum.count(String.graphemes(str))
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "length/1"
    end

    test "detects Enum.count in a guard-like comparison" do
      code = """
      defmodule Bad do
        def check(list, min_size) do
          if Enum.count(list) >= min_size, do: :ok, else: :error
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_enum_count_for_length
    end

    test "detects multiple Enum.count calls" do
      code = """
      defmodule Bad do
        def compare(a, b) do
          Enum.count(a) == Enum.count(b)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end

    test "detects Enum.count in assignment" do
      code = """
      defmodule Bad do
        def process(items) do
          n = Enum.count(items)
          Enum.reduce(0..(n - 1), 0, fn i, acc -> acc + i end)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "length/1"
    end

    # ---- Negative cases ----

    test "does not flag Enum.count/2 with predicate" do
      code = """
      defmodule Good do
        def count_positives(list) do
          Enum.count(list, &(&1 > 0))
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.count/2 with predicate in pipeline" do
      code = """
      defmodule Good do
        def count_big(list) do
          list |> Enum.count(&(&1 > 100))
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag length/1 (already correct)" do
      code = """
      defmodule Good do
        def size(list), do: length(list)
      end
      """

      assert check(code) == []
    end

    test "does not flag map_size/1" do
      code = """
      defmodule Good do
        def size(map), do: map_size(map)
      end
      """

      assert check(code) == []
    end

    test "does not flag MapSet.size/1" do
      code = """
      defmodule Good do
        def size(set), do: MapSet.size(set)
      end
      """

      assert check(code) == []
    end

    test "does not flag non-Enum count functions" do
      code = """
      defmodule Good do
        def count(list), do: MyModule.count(list)
      end
      """

      assert check(code) == []
    end
  end
end
