defmodule Credence.Pattern.NoSortThenAtCheckTest do
  use ExUnit.Case

  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoSortThenAt.check(ast, [])
  end

  # ── FLAGGED: atom direction + endpoint index ────────────────────────────

  describe "flags literal 0 and -1 indexes" do
    test "flags Enum.sort |> Enum.at(0)" do
      code = """
      defmodule M do
        def smallest(nums), do: Enum.sort(nums) |> Enum.at(0)
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end

    test "flags Enum.sort |> Enum.at(-1)" do
      code = """
      defmodule M do
        def largest(nums), do: Enum.sort(nums) |> Enum.at(-1)
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end

    test "flags Enum.sort(:desc) |> Enum.at(0)" do
      code = """
      defmodule M do
        def largest(nums), do: Enum.sort(nums, :desc) |> Enum.at(0)
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end

    test "flags nested Enum.at(Enum.sort(...), 0)" do
      code = """
      defmodule M do
        def smallest(nums), do: Enum.at(Enum.sort(nums), 0)
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end

    test "flags nested Enum.at(Enum.sort(...), -1)" do
      code = """
      defmodule M do
        def largest(nums), do: Enum.at(Enum.sort(nums), -1)
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end
  end

  # ── FLAGGED: function capture + endpoint index ──────────────────────────

  describe "flags function captures with endpoint index" do
    test "flags &>=/2 |> Enum.at(0)" do
      code = """
      defmodule M do
        def largest(nums), do: Enum.sort(nums, &>=/2) |> Enum.at(0)
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end

    test "flags &<=/2 |> Enum.at(0)" do
      code = """
      defmodule M do
        def smallest(nums), do: Enum.sort(nums, &<=/2) |> Enum.at(0)
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end

    test "flags &>=/2 |> Enum.at(-1)" do
      code = """
      defmodule M do
        def smallest(nums), do: Enum.sort(nums, &>=/2) |> Enum.at(-1)
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end

    test "flags nested Enum.at(Enum.sort(&>=/2), 0)" do
      code = """
      defmodule M do
        def largest(nums), do: Enum.at(Enum.sort(nums, &>=/2), 0)
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end
  end

  # ── FLAGGED: anonymous comparator + endpoint index ──────────────────────

  describe "flags anonymous comparators with endpoint index" do
    test "flags fn a, b -> a > b end |> Enum.at(0)" do
      code = """
      defmodule M do
        def largest(nums), do: Enum.sort(nums, fn a, b -> a > b end) |> Enum.at(0)
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end

    test "flags fn a, b -> a < b end |> Enum.at(-1)" do
      code = """
      defmodule M do
        def largest(nums), do: Enum.sort(nums, fn a, b -> a < b end) |> Enum.at(-1)
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end

    test "flags flipped fn a, b -> b < a end |> Enum.at(0)" do
      code = """
      defmodule M do
        def largest(nums), do: Enum.sort(nums, fn a, b -> b < a end) |> Enum.at(0)
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end

    test "flags nested Enum.at(Enum.sort(fn), -1)" do
      code = """
      defmodule M do
        def smallest(nums), do: Enum.at(Enum.sort(nums, fn a, b -> a > b end), -1)
      end
      """

      assert [%Issue{rule: :no_sort_then_at}] = check(code)
    end
  end

  # ── NOT FLAGGED: variable indexes ───────────────────────────────────────

  describe "does NOT flag variable indexes" do
    test "does not flag Enum.sort(:desc) |> Enum.at(k - 1)" do
      code = """
      defmodule M do
        def kth(nums, k), do: Enum.sort(nums, :desc) |> Enum.at(k - 1)
      end
      """

      assert check(code) == []
    end

    test "does not flag nested Enum.at(Enum.sort(...), div(n, 2))" do
      code = """
      defmodule M do
        def median(nums), do: Enum.at(Enum.sort(nums), div(length(nums), 2))
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.sort |> Enum.at(mid)" do
      code = """
      defmodule M do
        def middle(nums) do
          mid = div(length(nums), 2)
          Enum.sort(nums) |> Enum.at(mid)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag &>=/2 with variable index" do
      code = """
      defmodule M do
        def kth(nums, k), do: Enum.sort(nums, &>=/2) |> Enum.at(k - 1)
      end
      """

      assert check(code) == []
    end

    test "does not flag anonymous comparator with variable index" do
      code = """
      defmodule M do
        def kth(nums, k), do: Enum.sort(nums, fn a, b -> a > b end) |> Enum.at(k)
      end
      """

      assert check(code) == []
    end
  end

  # ── NOT FLAGGED: non-endpoint literal indexes ───────────────────────────

  describe "does NOT flag other literal indexes (no stdlib replacement)" do
    test "does not flag Enum.sort |> Enum.at(1)" do
      code = """
      defmodule M do
        def second_smallest(nums), do: Enum.sort(nums) |> Enum.at(1)
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.sort |> Enum.at(3)" do
      code = """
      defmodule M do
        def fourth(nums), do: Enum.sort(nums) |> Enum.at(3)
      end
      """

      assert check(code) == []
    end

    test "does not flag nested Enum.at(Enum.sort(...), 2)" do
      code = """
      defmodule M do
        def third(nums), do: Enum.at(Enum.sort(nums), 2)
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.sort |> Enum.at(-2)" do
      code = """
      defmodule M do
        def second_largest(nums), do: Enum.sort(nums) |> Enum.at(-2)
      end
      """

      assert check(code) == []
    end

    test "does not flag &>=/2 with non-endpoint literal" do
      code = """
      defmodule M do
        def third(nums), do: Enum.sort(nums, &>=/2) |> Enum.at(2)
      end
      """

      assert check(code) == []
    end
  end

  # ── NOT FLAGGED: direction cannot be resolved (can't determine min vs max) ─

  describe "does NOT flag unresolvable direction with endpoint index" do
    test "does not flag variable direction |> Enum.at(0)" do
      code = """
      defmodule M do
        def first(nums, dir), do: Enum.sort(nums, dir) |> Enum.at(0)
      end
      """

      assert check(code) == []
    end

    test "does not flag variable direction |> Enum.at(-1)" do
      code = """
      defmodule M do
        def last(nums, dir), do: Enum.sort(nums, dir) |> Enum.at(-1)
      end
      """

      assert check(code) == []
    end

    test "does not flag nested Enum.at(Enum.sort(nums, dir), 0)" do
      code = """
      defmodule M do
        def first(nums, dir), do: Enum.at(Enum.sort(nums, dir), 0)
      end
      """

      assert check(code) == []
    end

    test "does not flag opaque comparator |> Enum.at(0)" do
      code = """
      defmodule M do
        def first(nums), do: Enum.sort(nums, &MyModule.compare/2) |> Enum.at(0)
      end
      """

      assert check(code) == []
    end

    test "does not flag opaque comparator |> Enum.at(-1)" do
      code = """
      defmodule M do
        def last(nums), do: Enum.sort(nums, &MyModule.compare/2) |> Enum.at(-1)
      end
      """

      assert check(code) == []
    end
  end

  # ── NOT FLAGGED: unrelated patterns ─────────────────────────────────────

  describe "does NOT flag unrelated patterns" do
    test "does not flag plain Enum.at" do
      code = """
      defmodule M do
        def get(list, i), do: Enum.at(list, i)
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.sort |> Enum.take" do
      code = """
      defmodule M do
        def top3(nums), do: Enum.sort(nums, :desc) |> Enum.take(3)
      end
      """

      assert check(code) == []
    end
  end
end
