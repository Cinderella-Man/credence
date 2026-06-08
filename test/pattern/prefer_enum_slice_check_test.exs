defmodule Credence.Pattern.PreferEnumSliceCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.PreferEnumSlice

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

      assert check(PreferEnumSlice, code) == []
    end

    test "detects Enum.drop |> Enum.take pipeline" do
      code = """
      defmodule BadPipeline do
        def extract(graphemes, best_window_start, best_length) do
          graphemes
          |> Enum.drop(5)
          |> Enum.take(3)
        end
      end
      """

      issues = check(PreferEnumSlice, code)
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

      issues = check(PreferEnumSlice, code)
      assert length(issues) == 1
    end

    test "detects nested function calls (no pipes)" do
      code = """
      defmodule BadNested do
        def extract(list, start, len) do
          Enum.take(Enum.drop(list, 2), 5)
        end
      end
      """

      issues = check(PreferEnumSlice, code)
      assert length(issues) == 1
      assert hd(issues).rule == :prefer_enum_slice
    end

    test "detects single pipe Enum.drop |> Enum.take" do
      code = """
      defmodule SinglePipe do
        def extract(list, start, len) do
          Enum.drop(list, 2) |> Enum.take(5)
        end
      end
      """

      issues = check(PreferEnumSlice, code)
      assert length(issues) == 1
      assert hd(issues).rule == :prefer_enum_slice
    end

    test "detects pipeline inside anonymous function" do
      code = """
      Enum.map(list, fn x ->
        x
        |> Enum.drop(2)
        |> Enum.take(5)
      end)
      """

      assert length(check(PreferEnumSlice, code)) == 1
    end

    test "detects multiple occurrences" do
      code = """
      defmodule MultiOccurrence do
        def process(list) do
          a = Enum.drop(list, 0) |> Enum.take(5)
          b = Enum.drop(list, 3) |> Enum.take(10)
          {a, b}
        end
      end
      """

      issues = check(PreferEnumSlice, code)
      assert length(issues) == 2
    end

    # --- NEGATIVE CASES (should NOT flag) ---

    test "ignores reversed order (Enum.take |> Enum.drop)" do
      code = """
      defmodule ReversedOrder do
        def extract(list) do
          list
          |> Enum.take(10)
          |> Enum.drop(2)
        end
      end
      """

      assert check(PreferEnumSlice, code) == []
    end

    test "ignores drop/take with Stream" do
      code = """
      defmodule ValidStream do
        def extract(list) do
          list
          |> Stream.drop(5)
          |> Stream.take(5)
        end
      end
      """

      assert check(PreferEnumSlice, code) == []
    end

    test "ignores standalone Enum.drop" do
      code = """
      defmodule StandaloneDrop do
        def trim(list, n), do: Enum.drop(list, n)
      end
      """

      assert check(PreferEnumSlice, code) == []
    end

    test "ignores standalone Enum.take" do
      code = """
      defmodule StandaloneTake do
        def head(list, n), do: Enum.take(list, n)
      end
      """

      assert check(PreferEnumSlice, code) == []
    end

    test "ignores Enum.drop piped into something other than Enum.take" do
      code = """
      defmodule DropThenMap do
        def process(list) do
          list
          |> Enum.drop(5)
          |> Enum.map(&(&1 * 2))
        end
      end
      """

      assert check(PreferEnumSlice, code) == []
    end

    test "ignores something other than Enum.drop piped into Enum.take" do
      code = """
      defmodule FilterThenTake do
        def process(list) do
          list
          |> Enum.filter(&(&1 > 10))
          |> Enum.take(5)
        end
      end
      """

      assert check(PreferEnumSlice, code) == []
    end

    # --- NARROWING: only non-negative literal amounts (slice-equivalent) ---

    test "ignores variable amounts (could be negative at runtime)" do
      code = """
      Enum.drop(list, start) |> Enum.take(len)
      """

      assert check(PreferEnumSlice, code) == []
    end

    test "ignores negative drop amount" do
      code = """
      Enum.drop(list, -1) |> Enum.take(2)
      """

      assert check(PreferEnumSlice, code) == []
    end

    test "ignores negative take amount" do
      code = """
      Enum.drop(list, 1) |> Enum.take(-2)
      """

      assert check(PreferEnumSlice, code) == []
    end
  end
end
