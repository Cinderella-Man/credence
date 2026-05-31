defmodule Credence.Pattern.NoUniqThenCountTest do
  use ExUnit.Case

  alias Credence.Pattern.NoUniqThenCount

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoUniqThenCount.check(ast, [])
  end

  describe "NoUniqThenCount check" do
    test "detects Enum.uniq |> length() in pipeline" do
      code = """
      defmodule Bad do
        def count_unique(items) do
          items
          |> Enum.uniq()
          |> length()
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_uniq_then_count
      assert issue.message =~ "Enum.uniq"
      assert issue.message =~ "MapSet"
    end

    test "detects Enum.uniq |> Enum.count() in pipeline" do
      code = """
      defmodule Bad do
        def count_unique(items) do
          items
          |> Enum.uniq()
          |> Enum.count()
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_uniq_then_count
    end

    test "detects Enum.map |> Enum.uniq |> length" do
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

      [issue] = check(code)
      assert issue.rule == :no_uniq_then_count
    end

    test "detects nested in longer pipeline" do
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

      [issue] = check(code)
      assert issue.rule == :no_uniq_then_count
    end

    test "does not fire on Enum.uniq alone" do
      code = """
      defmodule Good do
        def unique_items(items) do
          items
          |> Enum.uniq()
        end
      end
      """

      assert check(code) == []
    end

    test "does not fire on Enum.uniq |> Enum.map" do
      code = """
      defmodule Good do
        def process(items) do
          items
          |> Enum.uniq()
          |> Enum.map(& &1 * 2)
        end
      end
      """

      assert check(code) == []
    end

    test "does not fire on Enum.uniq |> Enum.count(predicate)" do
      code = """
      defmodule Good do
        def count_unique_even(items) do
          items
          |> Enum.uniq()
          |> Enum.count(fn x -> rem(x, 2) == 0 end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not fire on MapSet.new |> MapSet.size" do
      code = """
      defmodule Good do
        def count_unique(items) do
          items
          |> MapSet.new()
          |> MapSet.size()
        end
      end
      """

      assert check(code) == []
    end
  end
end
