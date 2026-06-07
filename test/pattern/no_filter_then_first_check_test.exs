defmodule Credence.Pattern.NoFilterThenFirstCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoFilterThenFirst

  # ── FLAGGED: Stream.filter pipeline forms ──────────────────────────────
  #
  # Stream.filter is lazy, so `Stream.filter(coll, pred) |> Enum.at(0)`
  # evaluates `pred` only until the first match — identical to Enum.find/2,
  # including predicate side effects. Safe to rewrite.

  describe "flags Stream.filter |> Enum.at(0)" do
    test "flags Stream.filter |> Enum.at(0)" do
      code = """
      defmodule M do
        def first_even(nums), do: Stream.filter(nums, &even?/1) |> Enum.at(0)
      end
      """

      assert [%Issue{rule: :no_filter_then_first}] = check(NoFilterThenFirst, code)
    end

    test "flags with predicate function reference" do
      code = """
      defmodule M do
        def first_palindrome(nums) do
          nums
          |> Stream.filter(&palindrome?/1)
          |> Enum.at(0)
        end
      end
      """

      assert [%Issue{rule: :no_filter_then_first}] = check(NoFilterThenFirst, code)
    end

    test "flags inside longer pipeline" do
      code = """
      defmodule M do
        def first_even(n) do
          1
          |> Stream.iterate(&(&1 + 1))
          |> Stream.filter(&even?/1)
          |> Enum.at(0)
        end
      end
      """

      assert [%Issue{rule: :no_filter_then_first}] = check(NoFilterThenFirst, code)
    end
  end

  # ── FLAGGED: nested Stream.filter form ─────────────────────────────────

  describe "flags nested Enum.at(Stream.filter(...), 0)" do
    test "flags nested Stream.filter" do
      code = """
      defmodule M do
        def first_even(nums), do: Enum.at(Stream.filter(nums, &even?/1), 0)
      end
      """

      assert [%Issue{rule: :no_filter_then_first}] = check(NoFilterThenFirst, code)
    end
  end

  # ── NOT FLAGGED: eager Enum.filter (behaviour-changing) ────────────────
  #
  # Enum.filter is eager: it evaluates `pred` on EVERY element, while
  # Enum.find stops at the first match. A side-effecting or raising predicate
  # makes the two diverge, so these are deliberately left untouched.

  describe "does NOT flag eager Enum.filter" do
    test "does not flag Enum.filter |> Enum.at(0)" do
      code = """
      defmodule M do
        def first_even(nums), do: Enum.filter(nums, &even?/1) |> Enum.at(0)
      end
      """

      assert check(NoFilterThenFirst, code) == []
    end

    test "does not flag nested Enum.at(Enum.filter(...), 0)" do
      code = """
      defmodule M do
        def first_even(nums), do: Enum.at(Enum.filter(nums, &even?/1), 0)
      end
      """

      assert check(NoFilterThenFirst, code) == []
    end
  end

  # ── NOT FLAGGED: wrong index ───────────────────────────────────────────

  describe "does NOT flag non-zero indexes" do
    test "does not flag Stream.filter |> Enum.at(1)" do
      code = """
      defmodule M do
        def second_even(nums), do: Stream.filter(nums, &even?/1) |> Enum.at(1)
      end
      """

      assert check(NoFilterThenFirst, code) == []
    end

    test "does not flag Stream.filter |> Enum.at(-1)" do
      code = """
      defmodule M do
        def last_even(nums), do: Stream.filter(nums, &even?/1) |> Enum.at(-1)
      end
      """

      assert check(NoFilterThenFirst, code) == []
    end
  end

  # ── NOT FLAGGED: default arg ───────────────────────────────────────────

  describe "does NOT flag Enum.at with default" do
    test "does not flag Stream.filter |> Enum.at(0, :none)" do
      code = """
      defmodule M do
        def first_even(nums), do: Stream.filter(nums, &even?/1) |> Enum.at(0, :none)
      end
      """

      assert check(NoFilterThenFirst, code) == []
    end
  end

  # ── NOT FLAGGED: already idiomatic ─────────────────────────────────────

  describe "does NOT flag already idiomatic code" do
    test "does not flag Enum.find" do
      code = """
      defmodule M do
        def first_even(nums), do: Enum.find(nums, &even?/1)
      end
      """

      assert check(NoFilterThenFirst, code) == []
    end

    test "does not flag plain Stream.filter without at(0)" do
      code = """
      defmodule M do
        def evens(nums), do: Stream.filter(nums, &even?/1)
      end
      """

      assert check(NoFilterThenFirst, code) == []
    end

    test "does not flag plain Enum.at without filter" do
      code = """
      defmodule M do
        def get_first(nums), do: Enum.at(nums, 0)
      end
      """

      assert check(NoFilterThenFirst, code) == []
    end
  end
end
