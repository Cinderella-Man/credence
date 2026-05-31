defmodule Credence.Pattern.NoFilterThenNewTest do
  use ExUnit.Case

  alias Credence.Pattern.NoFilterThenNew

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoFilterThenNew.check(ast, [])
  end

  describe "NoFilterThenNew check" do
    test "detects Enum.filter |> MapSet.new(fn) in pipeline" do
      code = """
      defmodule Bad do
        def most_frequent(freq_map, max_freq) do
          freq_map
          |> Enum.filter(fn {_char, count} -> count == max_freq end)
          |> MapSet.new(fn {char, _count} -> char end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_filter_then_new
      assert issue.message =~ "Enum.filter"
      assert issue.message =~ "MapSet.new"
    end

    test "detects Enum.filter |> Map.new(fn) in pipeline" do
      code = """
      defmodule Bad do
        def filtered_map(items, threshold) do
          items
          |> Enum.filter(fn {_k, v} -> v > threshold end)
          |> Map.new(fn {k, v} -> {k, v * 2} end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_filter_then_new
      assert issue.message =~ "Map.new"
    end

    test "detects nested MapSet.new(Enum.filter(enum, pred), fn)" do
      code = """
      defmodule Bad do
        def to_set(items, pred, transform) do
          MapSet.new(Enum.filter(items, pred), transform)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_filter_then_new
      assert issue.message =~ "MapSet.new"
    end

    test "does not fire on Enum.filter |> MapSet.new/1 (no transform)" do
      code = """
      defmodule Good do
        def filtered_set(items, pred) do
          items
          |> Enum.filter(pred)
          |> MapSet.new()
        end
      end
      """

      assert check(code) == []
    end

    test "does not fire on Enum.filter |> Enum.map pipeline" do
      code = """
      defmodule Good do
        def filtered_mapped(items, pred, transform) do
          items
          |> Enum.filter(pred)
          |> Enum.map(transform)
        end
      end
      """

      assert check(code) == []
    end

    test "does not fire on MapSet.new/2 without preceding filter" do
      code = """
      defmodule Good do
        def to_set(items, transform) do
          items
          |> Enum.map(transform)
          |> MapSet.new()
        end
      end
      """

      assert check(code) == []
    end

    test "does not fire on unrelated pipeline" do
      code = """
      defmodule Good do
        def process(items) do
          items
          |> Enum.map(& &1 + 1)
          |> Enum.sum()
        end
      end
      """

      assert check(code) == []
    end
  end
end
