defmodule Credence.Pattern.NoListDuplicateFlattenFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoListDuplicateFlatten

  # ═══════════════════════════════════════════════════════════════════
  # FIXABLE — rewrites to Enum.flat_map(1..n, fn _ -> list end)
  # ═══════════════════════════════════════════════════════════════════

  describe "rewrites the Enum.concat / List.duplicate idiom" do
    test "nested form" do
      code = "Enum.concat(List.duplicate(list, 3))"

      expected = "Enum.flat_map(1..3, fn _ -> list end)"

      confirm_fix(fix(NoListDuplicateFlatten, code), expected)
    end

    test "piped form" do
      code = """
      list
      |> List.duplicate(3)
      |> Enum.concat()
      """

      expected = "Enum.flat_map(1..3, fn _ -> list end)"

      confirm_fix(fix(NoListDuplicateFlatten, code), expected)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NOT FIXABLE — left exactly as-is
  # ═══════════════════════════════════════════════════════════════════

  describe "leaves unsafe shapes untouched" do
    test "List.flatten variant (deep flatten)" do
      code = "List.flatten(List.duplicate(list, 3))"

      confirm_fix(fix(NoListDuplicateFlatten, code), code)
    end

    test "variable repetition count" do
      code = "Enum.concat(List.duplicate(list, n))"

      confirm_fix(fix(NoListDuplicateFlatten, code), code)
    end

    test "zero literal count" do
      code = "Enum.concat(List.duplicate(list, 0))"

      confirm_fix(fix(NoListDuplicateFlatten, code), code)
    end

    test "non-variable duplicated value" do
      code = "Enum.concat(List.duplicate([1, 2, 3], 3))"

      confirm_fix(fix(NoListDuplicateFlatten, code), code)
    end
  end
end
