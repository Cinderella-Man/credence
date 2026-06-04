defmodule Credence.Pattern.NoTautologicalIfFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoTautologicalIf

  defp fix(code) do
    result = Credence.RuleHelpers.apply_rule_fix(NoTautologicalIf, code, [])
    if String.ends_with?(result, "\n"), do: result, else: result <> "\n"
  end

  # ═══════════════════════════════════════════════════════════════════
  # BASIC FIXES
  # ═══════════════════════════════════════════════════════════════════

  describe "replaces tautological if with do-branch body" do
    test "simple variable" do
      input = """
      defp do_pass(list) do
        {swapped, result} = do_pass_recursive(list, false, [])
        if swapped do
          result
        else
          result
        end
      end
      """

      expected = """
      defp do_pass(list) do
        {swapped, result} = do_pass_recursive(list, false, [])
        result
      end
      """

      assert fix(input) == expected
    end

    test "inline form" do
      input = """
      def check(x) do
        if x > 0, do: value, else: value
      end
      """

      expected = """
      def check(x) do
        value
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OP — narrowed-out cases must be left untouched
  # ═══════════════════════════════════════════════════════════════════

  describe "leaves unsafe cases unchanged" do
    test "side-effecting condition" do
      code = """
      def check(x) do
        if launch_missiles() do
          :ok
        else
          :ok
        end
      end
      """

      assert fix(code) == code
    end

    test "condition that binds a variable" do
      code = """
      def check(x) do
        if (y = compute(x)) do
          y
        else
          y
        end
      end
      """

      assert fix(code) == code
    end

    test "body binds a variable" do
      code = """
      def check(x) do
        if flag do
          y = compute(x)
          y
        else
          y = compute(x)
          y
        end
      end
      """

      assert fix(code) == code
    end
  end
end
