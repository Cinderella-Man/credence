defmodule Credence.Pattern.PreferZipWithOverZipThenCountFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferZipWithOverZipThenCount

  # ── Pipeline form ──────────────────────────────────────────────────────

  describe "pipeline fix" do
    test "rewrites Enum.zip |> Enum.count(fn {x, y} -> ... end)" do
      confirm_fix(
        fix(
          PreferZipWithOverZipThenCount,
          "a |> Enum.zip(b) |> Enum.count(fn {x, y} -> x != y end)"
        ),
        "a |> Enum.zip_with(b, fn x, y -> x != y end) |> Enum.count(& &1)"
      )
    end

    test "rewrites Enum.zip(a, b) |> Enum.count(fn ...) (direct zip in pipeline)" do
      confirm_fix(
        fix(
          PreferZipWithOverZipThenCount,
          "Enum.zip(a, b) |> Enum.count(fn {x, y} -> x != y end)"
        ),
        "Enum.zip_with(a, b, fn x, y -> x != y end) |> Enum.count(& &1)"
      )
    end

    test "rewrites in longer pipeline" do
      input = """
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
          |> Enum.zip_with(b, fn x, y -> x != y end)
          |> Enum.count(& &1)
        end
      end
      """

      confirm_fix(fix(PreferZipWithOverZipThenCount, input), expected)
    end

    test "rewrites with complex predicate body" do
      confirm_fix(
        fix(
          PreferZipWithOverZipThenCount,
          "a |> Enum.zip(b) |> Enum.count(fn {x, y} -> rem(x, 2) == rem(y, 2) end)"
        ),
        "a |> Enum.zip_with(b, fn x, y -> rem(x, 2) == rem(y, 2) end) |> Enum.count(& &1)"
      )
    end
  end

  # ── Nested form ────────────────────────────────────────────────────────

  describe "nested fix" do
    test "rewrites Enum.count(Enum.zip(a, b), fn {x, y} -> ... end)" do
      confirm_fix(
        fix(
          PreferZipWithOverZipThenCount,
          "Enum.count(Enum.zip(a, b), fn {x, y} -> x != y end)"
        ),
        "Enum.zip_with(a, b, fn x, y -> x != y end) |> Enum.count(& &1)"
      )
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
  end
end
