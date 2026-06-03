defmodule Credence.Pattern.NoFilterThenMapTest do
  use ExUnit.Case

  alias Credence.Pattern.NoFilterThenMap

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoFilterThenMap.check(ast, [])
  end

  defp fix(code) do
    ast = Sourceror.parse_string!(code)
    patches = NoFilterThenMap.fix_patches(ast, source: code)

    case patches do
      [] -> code
      _ -> Sourceror.patch_string(code, patches)
    end
  end

  describe "NoFilterThenMap check" do
    test "detects Enum.filter |> Enum.map in pipeline" do
      code = """
      defmodule Bad do
        def prime_square_pairs(numbers) do
          numbers
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.filter(fn [first, second] -> prime?(first) and perfect_square?(second) end)
          |> Enum.map(fn [first, second] -> {first, second} end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_filter_then_map
      assert issue.message =~ "Enum.filter"
      assert issue.message =~ "Enum.map"
      assert issue.message =~ "for"
    end

    test "detects Enum.filter |> Enum.map with simple predicate" do
      code = """
      defmodule Bad do
        def evens_squared(numbers) do
          numbers
          |> Enum.filter(fn x -> rem(x, 2) == 0 end)
          |> Enum.map(fn x -> x * x end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_filter_then_map
    end

    test "detects with capture syntax" do
      code = """
      defmodule Bad do
        def positive_items(items) do
          items
          |> Enum.filter(&(&1 > 0))
          |> Enum.map(&(&1 * 2))
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_filter_then_map
    end

    test "does not fire on Enum.filter alone" do
      code = """
      defmodule Good do
        def evens(numbers) do
          numbers
          |> Enum.filter(fn x -> rem(x, 2) == 0 end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not fire on Enum.map alone" do
      code = """
      defmodule Good do
        def double(numbers) do
          numbers
          |> Enum.map(fn x -> x * 2 end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not fire on Enum.filter |> Enum.into" do
      code = """
      defmodule Good do
        def to_set(items, pred) do
          items
          |> Enum.filter(pred)
          |> Enum.into(MapSet.new())
        end
      end
      """

      assert check(code) == []
    end

    test "does not fire on Enum.map |> Enum.filter" do
      code = """
      defmodule Good do
        def process(items) do
          items
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 10 end)
        end
      end
      """

      assert check(code) == []
    end

    test "reports only one issue per filter-map pair (no duplicates in nested pipelines)" do
      code = """
      defmodule Bad do
        def process(items) do
          items
          |> Enum.filter(fn x -> rem(x, 2) == 0 end)
          |> Enum.map(fn x -> x * x end)
          |> Enum.sort()
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end
  end

  describe "NoFilterThenMap fix" do
    test "rewrites simple filter |> map to for comprehension" do
      result = fix("""
      defmodule Bad do
        def evens_squared(numbers) do
          numbers
          |> Enum.filter(fn x -> rem(x, 2) == 0 end)
          |> Enum.map(fn x -> x * x end)
        end
      end
      """)

      assert result =~ "for"
      assert result =~ "x <- numbers"
      assert result =~ "rem(x, 2) == 0"
      assert result =~ "x * x"
      refute result =~ "Enum.filter"
      refute result =~ "Enum.map"
    end

    test "rewrites tuple destructuring with merged bindings" do
      result = fix("""
      defmodule Bad do
        def most_common(frequencies, max_count) do
          frequencies
          |> Enum.filter(fn {_word, count} -> count == max_count end)
          |> Enum.map(fn {word, _count} -> word end)
        end
      end
      """)

      assert result =~ "for"
      assert result =~ "{word, count}"
      assert result =~ "<- frequencies"
      assert result =~ "count == max_count"
      assert result =~ "word"
      refute result =~ "Enum.filter"
      refute result =~ "Enum.map"
    end

    test "preserves trailing pipeline steps" do
      result = fix("""
      defmodule Bad do
        def process(items) do
          items
          |> Enum.filter(fn x -> rem(x, 2) == 0 end)
          |> Enum.map(fn x -> x * x end)
          |> Enum.sort()
        end
      end
      """)

      assert result =~ "for"
      assert result =~ "|> Enum.sort()"
    end

    test "does not fix capture syntax" do
      code = """
      defmodule Bad do
        def positive_items(items) do
          items
          |> Enum.filter(&(&1 > 0))
          |> Enum.map(&(&1 * 2))
        end
      end
      """

      assert fix(code) == code
    end

    test "does not fix lambda with guard" do
      code = """
      defmodule Bad do
        def process(items) do
          items
          |> Enum.filter(fn x when is_integer(x) -> x > 0 end)
          |> Enum.map(fn x -> x * 2 end)
        end
      end
      """

      assert fix(code) == code
    end

    test "does not fix incompatible binding shapes" do
      code = """
      defmodule Bad do
        def process(items) do
          items
          |> Enum.filter(fn {a, b} -> a > b end)
          |> Enum.map(fn x -> x * 2 end)
        end
      end
      """

      assert fix(code) == code
    end
  end
end
