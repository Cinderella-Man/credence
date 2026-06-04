defmodule Credence.Pattern.NoListDuplicateFlattenFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoListDuplicateFlatten

  defp fix(code) do
    ast = Sourceror.parse_string!(code)
    patches = NoListDuplicateFlatten.fix_patches(ast, source: code)

    case patches do
      [] -> code
      _ -> Sourceror.patch_string(code, patches)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIXABLE — rewrites to Enum.flat_map(1..n, fn _ -> list end)
  # ═══════════════════════════════════════════════════════════════════

  describe "rewrites the Enum.concat / List.duplicate idiom" do
    test "nested form" do
      code = """
      Enum.concat(List.duplicate(list, 3))
      """

      expected = """
      Enum.flat_map(1..3, fn _ -> list end)
      """

      assert fix(code) == expected
    end

    test "piped form" do
      code = """
      list
      |> List.duplicate(3)
      |> Enum.concat()
      """

      expected = """
      Enum.flat_map(1..3, fn _ -> list end)
      """

      assert fix(code) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NOT FIXABLE — left exactly as-is
  # ═══════════════════════════════════════════════════════════════════

  describe "leaves unsafe shapes untouched" do
    test "List.flatten variant (deep flatten)" do
      code = """
      List.flatten(List.duplicate(list, 3))
      """

      assert fix(code) == code
    end

    test "variable repetition count" do
      code = """
      Enum.concat(List.duplicate(list, n))
      """

      assert fix(code) == code
    end

    test "zero literal count" do
      code = """
      Enum.concat(List.duplicate(list, 0))
      """

      assert fix(code) == code
    end

    test "non-variable duplicated value" do
      code = """
      Enum.concat(List.duplicate([1, 2, 3], 3))
      """

      assert fix(code) == code
    end
  end
end
