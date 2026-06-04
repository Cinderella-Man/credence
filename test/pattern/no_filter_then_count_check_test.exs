defmodule Credence.Pattern.NoFilterThenCountCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoFilterThenCount

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoFilterThenCount.check(ast, [])
  end

  describe "NoFilterThenCount check" do
    test "detects Enum.filter |> length() in pipeline" do
      code = """
      defmodule Bad do
        def count_evens(numbers) do
          numbers
          |> Enum.filter(fn x -> rem(x, 2) == 0 end)
          |> length()
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_filter_then_count
      assert issue.message =~ "Enum.filter"
      assert issue.message =~ "length"
      assert issue.message =~ "Enum.count"
    end

    test "detects Enum.filter |> Enum.count() in pipeline" do
      code = """
      defmodule Bad do
        def count_evens(numbers) do
          numbers
          |> Enum.filter(fn x -> rem(x, 2) == 0 end)
          |> Enum.count()
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_filter_then_count
    end

    test "detects with capture syntax" do
      code = """
      defmodule Bad do
        def count_positives(items) do
          items
          |> Enum.filter(&(&1 > 0))
          |> length()
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_filter_then_count
    end

    test "detects in longer pipeline" do
      code = """
      defmodule Bad do
        def process(data) do
          data
          |> Enum.map(&to_string/1)
          |> Enum.filter(fn s -> String.length(s) > 3 end)
          |> length()
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_filter_then_count
    end

    test "detects nested length(Enum.filter(enum, pred))" do
      code = """
      defmodule Bad do
        def count_evens(numbers) do
          length(Enum.filter(numbers, fn x -> rem(x, 2) == 0 end))
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_filter_then_count
    end

    test "detects nested Enum.count(Enum.filter(enum, pred))" do
      code = """
      defmodule Bad do
        def count_evens(numbers) do
          Enum.count(Enum.filter(numbers, fn x -> rem(x, 2) == 0 end))
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_filter_then_count
    end

    test "detects multiple occurrences" do
      code = """
      defmodule Bad do
        def compare(a, b) do
          ac = a |> Enum.filter(&positive?/1) |> length()
          bc = b |> Enum.filter(&positive?/1) |> length()
          {ac, bc}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end

    # ---- Negative cases ----

    test "does not flag Enum.filter alone" do
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

    test "does not flag Enum.count with predicate (already idiomatic)" do
      code = """
      defmodule Good do
        def count_evens(numbers) do
          Enum.count(numbers, fn x -> rem(x, 2) == 0 end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.count in pipeline with predicate" do
      code = """
      defmodule Good do
        def count_evens(numbers) do
          numbers |> Enum.count(fn x -> rem(x, 2) == 0 end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag length without filter" do
      code = """
      defmodule Good do
        def size(list), do: length(list)
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.filter |> Enum.map" do
      code = """
      defmodule Good do
        def process(items) do
          items
          |> Enum.filter(fn x -> x > 0 end)
          |> Enum.map(fn x -> x * 2 end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.filter |> hd" do
      code = """
      defmodule Good do
        def first_positive(items) do
          items
          |> Enum.filter(fn x -> x > 0 end)
          |> hd()
        end
      end
      """

      assert check(code) == []
    end

    # ---- Narrowed-away cases: check must agree with fix ----
    # The nested fix only rewrites a 2-arg `Enum.filter(enum, pred)`. A 1-arg
    # `Enum.filter(x)` (which has no real arity-1 counterpart) is left unflagged
    # so check never reports a case the fix won't touch.

    test "does not flag nested length(Enum.filter(x)) with single-arg filter" do
      code = """
      defmodule Edge do
        def f(x), do: length(Enum.filter(x))
      end
      """

      assert check(code) == []
    end

    test "does not flag nested Enum.count(Enum.filter(x)) with single-arg filter" do
      code = """
      defmodule Edge do
        def f(x), do: Enum.count(Enum.filter(x))
      end
      """

      assert check(code) == []
    end
  end
end
