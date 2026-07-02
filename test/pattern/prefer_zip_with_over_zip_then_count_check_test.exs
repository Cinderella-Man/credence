defmodule Credence.Pattern.PreferZipWithOverZipThenCountCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferZipWithOverZipThenCount

  describe "PreferZipWithOverZipThenCount check" do
    test "flags Enum.zip |> Enum.count with tuple-destructuring fn (pipe form)" do
      code = """
      defmodule Bad do
        def diff_count(a, b) do
          a
          |> Enum.zip(b)
          |> Enum.count(fn {x, y} -> x != y end)
        end
      end
      """

      [issue] = check(PreferZipWithOverZipThenCount, code)
      assert issue.rule == :prefer_zip_with_over_zip_then_count
    end

    test "flags Enum.count(Enum.zip(a, b), fn ...) nested form" do
      code = """
      defmodule Bad do
        def diff_count(a, b) do
          Enum.count(Enum.zip(a, b), fn {x, y} -> x != y end)
        end
      end
      """

      [issue] = check(PreferZipWithOverZipThenCount, code)
      assert issue.rule == :prefer_zip_with_over_zip_then_count
    end

    test "flags in longer pipeline" do
      code = """
      defmodule Bad do
        def diff_count(a, b) do
          a
          |> Enum.map(&to_string/1)
          |> Enum.zip(b)
          |> Enum.count(fn {x, y} -> x != y end)
        end
      end
      """

      [issue] = check(PreferZipWithOverZipThenCount, code)
      assert issue.rule == :prefer_zip_with_over_zip_then_count
    end

    test "flags with complex predicate body" do
      code = """
      defmodule Bad do
        def parity_matches(a, b) do
          a
          |> Enum.zip(b)
          |> Enum.count(fn {x, y} -> rem(x, 2) == rem(y, 2) end)
        end
      end
      """

      [issue] = check(PreferZipWithOverZipThenCount, code)
      assert issue.rule == :prefer_zip_with_over_zip_then_count
    end

    test "detects multiple occurrences" do
      code = """
      defmodule Bad do
        def compare(a, b, c, d) do
          ac = a |> Enum.zip(b) |> Enum.count(fn {x, y} -> x != y end)
          bd = c |> Enum.zip(d) |> Enum.count(fn {x, y} -> x != y end)
          {ac, bd}
        end
      end
      """

      issues = check(PreferZipWithOverZipThenCount, code)
      assert length(issues) == 2
    end

    # ---- Negative cases ----

    test "does not flag Enum.zip_with (already idiomatic)" do
      code = """
      defmodule Good do
        def diff_count(a, b) do
          Enum.zip_with(a, b, fn x, y -> x != y end) |> Enum.count(& &1)
        end
      end
      """

      assert check(PreferZipWithOverZipThenCount, code) == []
    end

    test "does not flag Enum.zip |> Enum.count() without predicate" do
      code = """
      defmodule Good do
        def count_pairs(a, b) do
          a |> Enum.zip(b) |> Enum.count()
        end
      end
      """

      assert check(PreferZipWithOverZipThenCount, code) == []
    end

    test "does not flag Enum.zip |> Enum.count with non-tuple fn" do
      code = """
      defmodule Good do
        def count_items(a, b) do
          a |> Enum.zip(b) |> Enum.count(fn x -> x > 0 end)
        end
      end
      """

      assert check(PreferZipWithOverZipThenCount, code) == []
    end

    test "does not flag Enum.zip alone without count" do
      code = """
      defmodule Good do
        def pair(a, b) do
          a |> Enum.zip(b)
        end
      end
      """

      assert check(PreferZipWithOverZipThenCount, code) == []
    end
  end
end
