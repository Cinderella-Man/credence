defmodule Credence.Pattern.NoUniqThenCountCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoUniqThenCount

  describe "flags Enum.uniq piped into length/count" do
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

      [issue] = check(NoUniqThenCount, code)
      assert issue.rule == :no_uniq_then_count

      assert issue.message ==
               "`Enum.uniq/1` piped into `length/1` or `Enum.count/1` creates an " <>
                 "unnecessary intermediate list. Use `MapSet.new(enum) |> MapSet.size()` " <>
                 "instead — it deduplicates in a single pass with O(1) size lookup."
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

      assert [%{rule: :no_uniq_then_count}] = check(NoUniqThenCount, code)
    end

    test "uniq following a transform step" do
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

      assert [%{rule: :no_uniq_then_count}] = check(NoUniqThenCount, code)
    end

    test "uniq nested deeper in a longer pipeline" do
      code = """
      defmodule Bad do
        def process(data) do
          data
          |> Enum.filter(&valid?/1)
          |> Enum.uniq()
          |> Enum.count()
        end
      end
      """

      assert [%{rule: :no_uniq_then_count}] = check(NoUniqThenCount, code)
    end

    test "head-form uniq carrying its source as an argument" do
      code = """
      defmodule Bad do
        def count_unique(items) do
          Enum.uniq(items) |> Enum.count()
        end
      end
      """

      assert [%{rule: :no_uniq_then_count}] = check(NoUniqThenCount, code)
    end

    test "fires exactly once when more steps follow the count" do
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

      assert [%{rule: :no_uniq_then_count}] = check(NoUniqThenCount, code)
    end
  end

  describe "no issue — outside the safe core" do
    test "Enum.uniq alone" do
      code = """
      defmodule Good do
        def unique_items(items) do
          items
          |> Enum.uniq()
        end
      end
      """

      assert check(NoUniqThenCount, code) == []
    end

    test "Enum.uniq piped into Enum.map (used for further processing)" do
      code = """
      defmodule Good do
        def process(items) do
          items
          |> Enum.uniq()
          |> Enum.map(& &1 * 2)
        end
      end
      """

      assert check(NoUniqThenCount, code) == []
    end

    test "Enum.uniq piped into Enum.count(predicate) — a filtered count" do
      code = """
      defmodule Good do
        def count_unique_even(items) do
          items
          |> Enum.uniq()
          |> Enum.count(fn x -> rem(x, 2) == 0 end)
        end
      end
      """

      assert check(NoUniqThenCount, code) == []
    end

    test "MapSet.new piped into MapSet.size (already the target form)" do
      code = """
      defmodule Good do
        def count_unique(items) do
          items
          |> MapSet.new()
          |> MapSet.size()
        end
      end
      """

      assert check(NoUniqThenCount, code) == []
    end

    test "piped uniq with an extra argument is not Enum.uniq/1 (invalid arity)" do
      code = """
      defmodule Skip do
        def f(items) do
          items
          |> Enum.uniq(:by)
          |> length()
        end
      end
      """

      assert check(NoUniqThenCount, code) == []
    end

    test "head uniq with no argument is not Enum.uniq/1 (invalid arity)" do
      code = """
      defmodule Skip do
        def f do
          Enum.uniq() |> length()
        end
      end
      """

      assert check(NoUniqThenCount, code) == []
    end

    test "uniq_by is a different operation" do
      code = """
      defmodule Skip do
        def f(items) do
          items
          |> Enum.uniq_by(&id/1)
          |> length()
        end
      end
      """

      assert check(NoUniqThenCount, code) == []
    end
  end
end
