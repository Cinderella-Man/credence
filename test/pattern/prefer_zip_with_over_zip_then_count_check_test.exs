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

    test "flags Enum.zip(a, b) at the pipe head" do
      code = """
      defmodule Bad do
        def diff_count(a, b) do
          Enum.zip(a, b) |> Enum.count(fn {x, y} -> x != y end)
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

    test "flags underscore-prefixed variables in the pattern" do
      code = """
      defmodule Bad do
        def truthy_seconds(a, b) do
          a |> Enum.zip(b) |> Enum.count(fn {_x, y} -> y end)
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

    test "flags exactly once when more steps follow the count" do
      code = """
      defmodule Bad do
        def diff_count_plus_one(a, b) do
          a
          |> Enum.zip(b)
          |> Enum.count(fn {x, y} -> x != y end)
          |> Kernel.+(1)
        end
      end
      """

      [issue] = check(PreferZipWithOverZipThenCount, code)
      assert issue.rule == :prefer_zip_with_over_zip_then_count
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

    test "does not flag Enum.zip/1 at the pipe head (list of enumerables)" do
      # Real zip/1: Enum.zip_with/2 hands its fun a LIST, so a fn x, y
      # rewrite would raise BadArityError where the original returns a count.
      code = """
      defmodule Good do
        def diff_count(enums) do
          Enum.zip(enums) |> Enum.count(fn {x, y} -> x != y end)
        end
      end
      """

      assert check(PreferZipWithOverZipThenCount, code) == []
    end

    test "does not flag a pipe-fed 2-argument zip (nonexistent Enum.zip/3)" do
      code = """
      defmodule Good do
        def broken(x, a, b) do
          x |> Enum.zip(a, b) |> Enum.count(fn {p, q} -> p == q end)
        end
      end
      """

      assert check(PreferZipWithOverZipThenCount, code) == []
    end

    test "does not flag a piped nested count (nonexistent Enum.count/3)" do
      code = """
      defmodule Good do
        def broken(x, a, b) do
          x |> Enum.count(Enum.zip(a, b), fn {p, q} -> p == q end)
        end
      end
      """

      assert check(PreferZipWithOverZipThenCount, code) == []
    end

    test "does not flag a pinned variable in the pattern" do
      code = """
      defmodule Good do
        def count_x(a, b, x) do
          a |> Enum.zip(b) |> Enum.count(fn {^x, y} -> y end)
        end
      end
      """

      assert check(PreferZipWithOverZipThenCount, code) == []
    end

    test "does not flag nested destructuring in the pattern" do
      code = """
      defmodule Good do
        def count_matching_values(pairs, ys) do
          pairs |> Enum.zip(ys) |> Enum.count(fn {{_k, v}, y} -> v == y end)
        end
      end
      """

      assert check(PreferZipWithOverZipThenCount, code) == []
    end

    test "does not flag a literal in the pattern" do
      code = """
      defmodule Good do
        def count_ones(a, b) do
          a |> Enum.zip(b) |> Enum.count(fn {1, y} -> y end)
        end
      end
      """

      assert check(PreferZipWithOverZipThenCount, code) == []
    end

    test "does not flag a guarded fn" do
      code = """
      defmodule Good do
        def count_pos_diff(a, b) do
          a |> Enum.zip(b) |> Enum.count(fn {x, y} when x > 0 -> x != y end)
        end
      end
      """

      assert check(PreferZipWithOverZipThenCount, code) == []
    end

    test "does not flag a multi-clause fn" do
      code = """
      defmodule Good do
        def count_diff(a, b) do
          a
          |> Enum.zip(b)
          |> Enum.count(fn
            {x, y} -> x != y
            _ -> false
          end)
        end
      end
      """

      assert check(PreferZipWithOverZipThenCount, code) == []
    end

    test "does not flag a capture predicate" do
      code = """
      defmodule Good do
        def count_diff(a, b) do
          a |> Enum.zip(b) |> Enum.count(&(elem(&1, 0) != elem(&1, 1)))
        end
      end
      """

      assert check(PreferZipWithOverZipThenCount, code) == []
    end
  end
end
