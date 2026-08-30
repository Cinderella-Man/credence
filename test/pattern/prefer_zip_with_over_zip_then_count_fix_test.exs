defmodule Credence.Pattern.PreferZipWithOverZipThenCountFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferZipWithOverZipThenCount

  # ── Pipeline form ──────────────────────────────────────────────────────

  describe "pipeline fix" do
    test "rewrites Enum.zip |> Enum.count(fn {x, y} -> ... end)" do
      code = "a |> Enum.zip(b) |> Enum.count(fn {x, y} -> x != y end)"

      expected =
        "a |> Enum.zip_with(b, fn x, y -> {x, y} end) |> Enum.count(fn {x, y} -> x != y end)"

      confirm_fix(fix(PreferZipWithOverZipThenCount, code), expected)
    end

    test "rewrites Enum.zip(a, b) |> Enum.count(fn ...) (direct zip at pipe head)" do
      code = "Enum.zip(a, b) |> Enum.count(fn {x, y} -> x != y end)"

      expected =
        "Enum.zip_with(a, b, fn x, y -> {x, y} end) |> Enum.count(fn {x, y} -> x != y end)"

      confirm_fix(fix(PreferZipWithOverZipThenCount, code), expected)
    end

    test "rewrites in longer pipeline" do
      code = """
      defmodule M do
        def diff_count(a, b) do
          a
          |> Enum.map(&to_string/1)
          |> Enum.zip(b)
          |> Enum.count(fn {x, y} -> x != y end)
        end
      end
      """

      expected = """
      defmodule M do
        def diff_count(a, b) do
          a
          |> Enum.map(&to_string/1)
          |> Enum.zip_with(b, fn x, y -> {x, y} end)
          |> Enum.count(fn {x, y} -> x != y end)
        end
      end
      """

      confirm_fix(fix(PreferZipWithOverZipThenCount, code), expected)
    end

    test "rewrites with complex predicate body" do
      code = "a |> Enum.zip(b) |> Enum.count(fn {x, y} -> rem(x, 2) == rem(y, 2) end)"

      expected =
        "a |> Enum.zip_with(b, fn x, y -> {x, y} end) |> Enum.count(fn {x, y} -> rem(x, 2) == rem(y, 2) end)"

      confirm_fix(fix(PreferZipWithOverZipThenCount, code), expected)
    end

    test "rewrites when more steps follow the count" do
      code = "a |> Enum.zip(b) |> Enum.count(fn {x, y} -> x != y end) |> Kernel.+(1)"

      expected =
        "a |> Enum.zip_with(b, fn x, y -> {x, y} end) |> Enum.count(fn {x, y} -> x != y end) |> Kernel.+(1)"

      confirm_fix(fix(PreferZipWithOverZipThenCount, code), expected)
    end
  end

  # ── Nested form ────────────────────────────────────────────────────────

  describe "nested fix" do
    test "rewrites Enum.count(Enum.zip(a, b), fn {x, y} -> ... end)" do
      code = "Enum.count(Enum.zip(a, b), fn {x, y} -> x != y end)"

      expected =
        "Enum.zip_with(a, b, fn x, y -> {x, y} end) |> Enum.count(fn {x, y} -> x != y end)"

      confirm_fix(fix(PreferZipWithOverZipThenCount, code), expected)
    end

    test "rewrites the nested form at a pipe head" do
      code = "Enum.count(Enum.zip(a, b), fn {x, y} -> x != y end) |> Kernel.+(1)"

      expected =
        "Enum.zip_with(a, b, fn x, y -> {x, y} end) |> Enum.count(fn {x, y} -> x != y end) |> Kernel.+(1)"

      confirm_fix(fix(PreferZipWithOverZipThenCount, code), expected)
    end
  end

  # ── Non-fixable ────────────────────────────────────────────────────────

  describe "does not fix non-matching patterns" do
    test "leaves Enum.zip_with alone unchanged" do
      code = "Enum.zip_with(a, b, fn x, y -> x != y end) |> Enum.count(& &1)"

      confirm_fix(fix(PreferZipWithOverZipThenCount, code), code)
    end

    test "leaves Enum.zip |> Enum.count() without predicate unchanged" do
      code = "a |> Enum.zip(b) |> Enum.count()"

      confirm_fix(fix(PreferZipWithOverZipThenCount, code), code)
    end

    test "leaves Enum.zip alone unchanged" do
      code = "a |> Enum.zip(b)"

      confirm_fix(fix(PreferZipWithOverZipThenCount, code), code)
    end

    test "leaves Enum.zip/1 at the pipe head unchanged" do
      code = "Enum.zip(enums) |> Enum.count(fn {x, y} -> x != y end)"

      confirm_fix(fix(PreferZipWithOverZipThenCount, code), code)
    end

    test "leaves a pipe-fed 2-argument zip unchanged" do
      code = "x |> Enum.zip(a, b) |> Enum.count(fn {p, q} -> p == q end)"

      confirm_fix(fix(PreferZipWithOverZipThenCount, code), code)
    end

    test "leaves a piped nested count unchanged" do
      code = "x |> Enum.count(Enum.zip(a, b), fn {p, q} -> p == q end)"

      confirm_fix(fix(PreferZipWithOverZipThenCount, code), code)
    end

    test "leaves a pinned pattern unchanged" do
      code = "a |> Enum.zip(b) |> Enum.count(fn {^x, y} -> y end)"

      confirm_fix(fix(PreferZipWithOverZipThenCount, code), code)
    end

    test "leaves nested destructuring unchanged" do
      code = "pairs |> Enum.zip(ys) |> Enum.count(fn {{_k, v}, y} -> v == y end)"

      confirm_fix(fix(PreferZipWithOverZipThenCount, code), code)
    end

    test "leaves a guarded fn unchanged" do
      code = "a |> Enum.zip(b) |> Enum.count(fn {x, y} when x > 0 -> x != y end)"

      confirm_fix(fix(PreferZipWithOverZipThenCount, code), code)
    end
  end
end
