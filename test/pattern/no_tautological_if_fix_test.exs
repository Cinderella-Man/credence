defmodule Credence.Pattern.NoTautologicalIfFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoTautologicalIf

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

      assert fix(NoTautologicalIf, input) == expected
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

      assert fix(NoTautologicalIf, input) == expected
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

      assert fix(NoTautologicalIf, code) == code
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

      assert fix(NoTautologicalIf, code) == code
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

      assert fix(NoTautologicalIf, code) == code
    end
  end
end
