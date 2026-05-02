defmodule Credence.Rule.PreferEnumSliceTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.PreferEnumSlice.check(ast, [])
  end

  describe "PreferEnumSlice" do
    test "passes when using Enum.slice" do
      code = """
      defmodule GoodSlice do
        def extract(list, start, len) do
          list
          |> Enum.slice(start, len)
        end
      end
      """

      assert check(code) == []
    end

    test "detects Enum.drop |> Enum.take pipeline" do
      code = """
      defmodule BadPipeline do
        def extract(graphemes, best_window_start, best_length) do
          graphemes
          |> Enum.drop(best_window_start)
          |> Enum.take(best_length)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :prefer_enum_slice
      assert issue.message =~ "Enum.slice/3"
      assert issue.meta.line != nil
    end

    test "detects deeply nested Enum.drop |> Enum.take pipeline" do
      code = """
      defmodule DeeplyNested do
        def process(list) do
          list
          |> Enum.map(&(&1 * 2))
          |> Enum.filter(&(&1 > 10))
          |> Enum.drop(5)
          |> Enum.take(3)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects nested function calls (no pipes)" do
      code = """
      defmodule BadNested do
        def extract(list, start, len) do
          Enum.take(Enum.drop(list, start), len)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :prefer_enum_slice
    end

    test "ignores reversed order (Enum.take |> Enum.drop)" do
      code = """
      defmodule ReversedOrder do
        def extract(list) do
          # This is not functionally equivalent to a single slice,
          # so we shouldn't flag it.
          list
          |> Enum.take(10)
          |> Enum.drop(2)
        end
      end
      """

      assert check(code) == []
    end

    test "ignores drop/take with Stream" do
      code = """
      defmodule ValidStream do
        def extract(list) do
          # Streams evaluate lazily, keeping drop/take might be intentional
          list
          |> Stream.drop(5)
          |> Stream.take(5)
        end
      end
      """

      assert check(code) == []
    end
  end
end
