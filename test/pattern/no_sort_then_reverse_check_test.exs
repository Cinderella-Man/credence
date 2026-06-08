defmodule Credence.Pattern.NoSortThenReverseCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoSortThenReverse

  # ── FLAGGED: atom direction ─────────────────────────────────────────────

  describe "flags sort then reverse with known direction" do
    test "pipeline default asc" do
      code = """
      defmodule M do
        def f(x), do: x |> Enum.sort() |> Enum.reverse()
      end
      """

      assert [%Issue{rule: :no_sort_then_reverse}] = check(NoSortThenReverse, code)
    end

    test "pipeline explicit :asc" do
      code = """
      defmodule M do
        def f(x), do: x |> Enum.sort(:asc) |> Enum.reverse()
      end
      """

      assert [%Issue{rule: :no_sort_then_reverse}] = check(NoSortThenReverse, code)
    end

    test "pipeline :desc" do
      code = """
      defmodule M do
        def f(x), do: x |> Enum.sort(:desc) |> Enum.reverse()
      end
      """

      assert [%Issue{rule: :no_sort_then_reverse}] = check(NoSortThenReverse, code)
    end

    test "nested call" do
      code = """
      defmodule M do
        def f(x), do: Enum.reverse(Enum.sort(x))
      end
      """

      assert [%Issue{rule: :no_sort_then_reverse}] = check(NoSortThenReverse, code)
    end

    test "longer pipeline" do
      code =
        """
        defmodule M do
          def f(x), do: x |> Enum.filter(&(&1 > 0)) |> Enum.sort() |> Enum.reverse()
        end
        """

      assert [%Issue{rule: :no_sort_then_reverse}] = check(NoSortThenReverse, code)
    end

    test "direct call piped to reverse" do
      code = """
      defmodule M do
        def f(x), do: Enum.sort(x) |> Enum.reverse()
      end
      """

      assert [%Issue{rule: :no_sort_then_reverse}] = check(NoSortThenReverse, code)
    end
  end

  # ── FLAGGED: function captures ──────────────────────────────────────────

  describe "flags sort with captures then reverse" do
    test "&>=/2 pipeline" do
      code = """
      defmodule M do
        def f(x), do: Enum.sort(x, &>=/2) |> Enum.reverse()
      end
      """

      assert [%Issue{rule: :no_sort_then_reverse}] = check(NoSortThenReverse, code)
    end

    test "&<=/2 pipeline" do
      code = """
      defmodule M do
        def f(x), do: Enum.sort(x, &<=/2) |> Enum.reverse()
      end
      """

      assert [%Issue{rule: :no_sort_then_reverse}] = check(NoSortThenReverse, code)
    end

    test "&>=/2 nested" do
      code = """
      defmodule M do
        def f(x), do: Enum.reverse(Enum.sort(x, &>=/2))
      end
      """

      assert [%Issue{rule: :no_sort_then_reverse}] = check(NoSortThenReverse, code)
    end
  end

  # ── FLAGGED: anonymous comparators ──────────────────────────────────────

  describe "flags sort with anonymous comparator then reverse" do
    test "fn a, b -> a > b end pipeline" do
      code =
        """
        defmodule M do
          def f(x), do: Enum.sort(x, fn a, b -> a > b end) |> Enum.reverse()
        end
        """

      assert [%Issue{rule: :no_sort_then_reverse}] = check(NoSortThenReverse, code)
    end

    test "fn a, b -> a < b end nested" do
      code =
        """
        defmodule M do
          def f(x), do: Enum.reverse(Enum.sort(x, fn a, b -> a < b end))
        end
        """

      assert [%Issue{rule: :no_sort_then_reverse}] = check(NoSortThenReverse, code)
    end

    test "flipped fn a, b -> b < a end pipeline" do
      code =
        """
        defmodule M do
          def f(x), do: Enum.sort(x, fn a, b -> b < a end) |> Enum.reverse()
        end
        """

      assert [%Issue{rule: :no_sort_then_reverse}] = check(NoSortThenReverse, code)
    end
  end

  # ── NOT FLAGGED: unresolvable direction ─────────────────────────────────

  describe "does NOT flag unresolvable direction" do
    test "variable direction" do
      code = """
      defmodule M do
        def f(x, dir), do: Enum.sort(x, dir) |> Enum.reverse()
      end
      """

      assert check(NoSortThenReverse, code) == []
    end

    test "opaque comparator" do
      code =
        """
        defmodule M do
          def f(x), do: Enum.sort(x, &MyModule.compare/2) |> Enum.reverse()
        end
        """

      assert check(NoSortThenReverse, code) == []
    end
  end

  # ── NOT FLAGGED: unrelated patterns ─────────────────────────────────────

  describe "does NOT flag unrelated patterns" do
    test "sort with :desc and no reverse" do
      code = """
      defmodule M do
        def f(x), do: Enum.sort(x, :desc) |> Enum.take(3)
      end
      """

      assert check(NoSortThenReverse, code) == []
    end

    test "reverse without preceding sort" do
      code = """
      defmodule M do
        def f(x), do: Enum.reverse(x)
      end
      """

      assert check(NoSortThenReverse, code) == []
    end
  end
end
