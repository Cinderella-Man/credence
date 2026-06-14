defmodule Credence.Pattern.NoUniqThenCountFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoUniqThenCount

  describe "rewrites uniq-then-count to MapSet" do
    test "piped uniq into length()" do
      code = """
      defmodule Bad do
        def count_unique(items) do
          items
          |> Enum.uniq()
          |> length()
        end
      end
      """

      expected = """
      defmodule Bad do
        def count_unique(items) do
          items
          |> MapSet.new()
          |> MapSet.size()
        end
      end
      """

      confirm_fix(fix(NoUniqThenCount, code), expected)
    end

    test "piped uniq into Enum.count()" do
      code = """
      defmodule Bad do
        def count_unique(items) do
          items
          |> Enum.uniq()
          |> Enum.count()
        end
      end
      """

      expected = """
      defmodule Bad do
        def count_unique(items) do
          items
          |> MapSet.new()
          |> MapSet.size()
        end
      end
      """

      confirm_fix(fix(NoUniqThenCount, code), expected)
    end

    test "uniq following a transform step leaves the prefix untouched" do
      code = """
      defmodule Bad do
        def count_unique_transformed(words) do
          words
          |> Enum.map(&transform/1)
          |> Enum.uniq()
          |> length()
        end
      end
      """

      expected = """
      defmodule Bad do
        def count_unique_transformed(words) do
          words
          |> Enum.map(&transform/1)
          |> MapSet.new()
          |> MapSet.size()
        end
      end
      """

      confirm_fix(fix(NoUniqThenCount, code), expected)
    end

    test "head-form uniq carries its source into MapSet.new" do
      code = """
      defmodule Bad do
        def count_unique(items) do
          Enum.uniq(items) |> Enum.count()
        end
      end
      """

      expected = """
      defmodule Bad do
        def count_unique(items) do
          MapSet.new(items) |> MapSet.size()
        end
      end
      """

      confirm_fix(fix(NoUniqThenCount, code), expected)
    end

    test "trailing steps after the count are preserved" do
      code = """
      defmodule Bad do
        def f(items) do
          items
          |> Enum.uniq()
          |> length()
          |> Kernel.+(1)
        end
      end
      """

      expected = """
      defmodule Bad do
        def f(items) do
          items
          |> MapSet.new()
          |> MapSet.size()
          |> Kernel.+(1)
        end
      end
      """

      confirm_fix(fix(NoUniqThenCount, code), expected)
    end
  end

  describe "no-ops outside the safe core" do
    test "Enum.uniq alone" do
      code = """
      defmodule Good do
        def unique_items(items) do
          items
          |> Enum.uniq()
        end
      end
      """

      confirm_fix(fix(NoUniqThenCount, code), code)
    end

    test "Enum.uniq piped into Enum.map" do
      code = """
      defmodule Good do
        def process(items) do
          items
          |> Enum.uniq()
          |> Enum.map(& &1 * 2)
        end
      end
      """

      confirm_fix(fix(NoUniqThenCount, code), code)
    end

    test "Enum.uniq piped into Enum.count(predicate)" do
      code = """
      defmodule Good do
        def count_unique_even(items) do
          items
          |> Enum.uniq()
          |> Enum.count(fn x -> rem(x, 2) == 0 end)
        end
      end
      """

      confirm_fix(fix(NoUniqThenCount, code), code)
    end
  end

  describe "round-trip" do
    test "fixed code raises no further issues" do
      code = """
      defmodule Bad do
        def count_unique(items) do
          items
          |> Enum.uniq()
          |> length()
        end
      end
      """

      assert check(NoUniqThenCount, fix(NoUniqThenCount, code)) == []
    end

    test "fixed code is valid Elixir" do
      code = """
      defmodule Bad do
        def count_unique(items) do
          Enum.uniq(items) |> Enum.count()
        end
      end
      """

      assert valid_syntax?(fix(NoUniqThenCount, code))
    end
  end
end
