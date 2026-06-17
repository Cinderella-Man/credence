defmodule Credence.BehaviourEquivalenceSelfTest do
  @moduledoc """
  Tests for the checker `assert_equivalent`, not for any rule.

  `assert_equivalent` is how we prove a rule's rewrite is safe: it runs the
  original code and the rewritten code on several inputs and checks they give the
  same answer. Before (and after) that comparison it runs four safety checks and
  refuses the test if any of them fails:

    1. the rule must actually apply to the snippet (otherwise nothing is tested),
    2. the rewrite must actually change the code (otherwise nothing is compared),
    3. there must be at least 3 inputs (one or two is too few to trust),
    4. the inputs must make the original behave differently (at least two distinct
       results) — otherwise a constant fix would pass without testing anything.

  Without these checks, a lazy or broken test could pass while really testing
  nothing. The tests below hand `assert_equivalent` a deliberately broken setup
  and confirm it raises an error — one test per check — plus correct setups
  (including a constant-by-design rule that opts out of check 4) that confirm the
  normal cases still pass.

  These test the checker itself, so they live outside `test/pattern/` (where the
  per-rule tests live).
  """

  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoLengthComparisonForEmpty
  alias Credence.Pattern.NoTautologicalIf

  # Check 2 needs a rule that finds a problem but offers no fix. None of the real
  # rules behave that way (they all fix what they find), so here is a fake one:
  # `check` says "there's a problem", `fix_patches` returns [] (no change).
  defmodule FindsProblemButOffersNoFix do
    use Credence.Pattern.Rule

    @impl true
    def check(_ast, _opts), do: [%Credence.Issue{rule: :no_fix, message: "fake problem"}]

    @impl true
    def fix_patches(_ast, _opts), do: []
  end

  describe "assert_equivalent refuses a broken test setup" do
    test "fewer than 3 inputs is rejected" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_equivalent("length(list) == 0",
          rule: NoLengthComparisonForEmpty,
          vars: [:list],
          # Only 2 inputs — the checker wants at least 3.
          inputs: [[1, 2, 3], [4, 5]]
        )
      end
    end

    test "a snippet the rule does not apply to is rejected" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_equivalent("length(list) == 100",
          # 100 is outside the 0–5 range this rule rewrites, so it does nothing here.
          rule: NoLengthComparisonForEmpty,
          vars: [:list],
          inputs: [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
        )
      end
    end

    test "a snippet the rewrite leaves unchanged is rejected" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_equivalent("list",
          # This fake rule finds a problem but makes no change, so nothing is compared.
          rule: FindsProblemButOffersNoFix,
          vars: [:list],
          inputs: [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
        )
      end
    end

    test "inputs that all produce the same result are rejected (no discriminating power)" do
      assert_raise ExUnit.AssertionError, fn ->
        # Both branches are `:v`, so the original returns `:v` for every input —
        # the inputs can't tell a correct fix from a wrong one. Without an explicit
        # opt-out, this must be rejected.
        assert_equivalent("if x > 0, do: :v, else: :v",
          rule: NoTautologicalIf,
          vars: [:x],
          inputs: [1, 2, 3]
        )
      end
    end
  end

  describe "assert_equivalent accepts a correct test setup" do
    # If the three tests above raised for some unrelated reason, this would catch
    # it: a real rule, a snippet it applies to, and 3 inputs must pass cleanly.
    test "real rule + applicable snippet + 3 inputs passes" do
      assert assert_equivalent("length(list) == 0",
               rule: NoLengthComparisonForEmpty,
               vars: [:list],
               # Include an empty list so the original gives 2 distinct results.
               inputs: [[1, 2, 3], [], [4, 5, 6]]
             ) == :ok
    end

    test "uniform results are allowed with an explicit allow_constant_output: true" do
      assert assert_equivalent("if x > 0, do: :v, else: :v",
               rule: NoTautologicalIf,
               vars: [:x],
               inputs: [1, 2, 3],
               allow_constant_output: true
             ) == :ok
    end
  end
end
