defmodule Credence.Pattern.PreferRemoveUnusedPrivateFnParamFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferRemoveUnusedPrivateFnParam

  # ═══════════════════════════════════════════════════════════════════
  # REWRITES — removes an unused, un-underscored parameter
  # ═══════════════════════════════════════════════════════════════════

  describe "removes unused private function parameter" do
    test "single clause — removes non-underscore unused param and updates call site" do
      input = """
      defmodule M do
        def run(x), do: compute(x, nil)
        defp compute(x, table), do: x + 1
      end
      """

      expected = """
      defmodule M do
        def run(x), do: compute(x)
        defp compute(x), do: x + 1
      end
      """

      confirm_fix(fix(PreferRemoveUnusedPrivateFnParam, input), expected)
    end

    test "multi-clause — removes unused param from all clauses and call sites" do
      input = """
      defmodule M do
        def run(list), do: process(list, :unused)

        defp process([], extra), do: 0
        defp process([h | t], extra), do: h + process(t, nil)
      end
      """

      expected = """
      defmodule M do
        def run(list), do: process(list)

        defp process([]), do: 0
        defp process([h | t]), do: h + process(t)
      end
      """

      confirm_fix(fix(PreferRemoveUnusedPrivateFnParam, input), expected)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SAFETY — must NOT modify
  # ═══════════════════════════════════════════════════════════════════

  describe "does not modify code without the anti-pattern" do
    test "all params used" do
      input = """
      defmodule M do
        defp compute(x, y), do: x + y
      end
      """

      confirm_fix(fix(PreferRemoveUnusedPrivateFnParam, input), input)
    end

    test "underscore-prefixed unused param is left alone" do
      input = """
      defmodule M do
        defp compute(x, _unused), do: x + 1
      end
      """

      confirm_fix(fix(PreferRemoveUnusedPrivateFnParam, input), input)
    end

    test "param reused in another argument's pattern is left alone" do
      input = """
      defmodule M do
        defp check(pk, [pk | rest]), do: rest
        defp check(pk, []), do: []
      end
      """

      confirm_fix(fix(PreferRemoveUnusedPrivateFnParam, input), input)
    end

    test "public function with unused param" do
      input = """
      defmodule M do
        def compute(x, _unused), do: x + 1
      end
      """

      confirm_fix(fix(PreferRemoveUnusedPrivateFnParam, input), input)
    end

    test "param used in one clause" do
      input = """
      defmodule M do
        defp compute([], table), do: table
        defp compute([_h | t], table), do: compute(t, table)
      end
      """

      confirm_fix(fix(PreferRemoveUnusedPrivateFnParam, input), input)
    end
  end
end
