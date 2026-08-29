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

  defmodule ExternalExample do
    def run({parent, value}) do
      send(parent, {:external_example_called, value})
      {:external, value}
    end
  end

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

  # ── T3.5: the module rename must move internal references too ──────────

  describe "assert_equivalent_module/2 with a struct-defining module" do
    # The before/after modules are renamed so both can live in one VM. That
    # rename used to be a `String.replace` of the `defmodule` line alone, so a
    # module referring to ITSELF — the ordinary way to write a struct literal —
    # kept pointing at the original name and either failed to compile or, worse,
    # silently resolved to a stale version compiled by an earlier test.
    #
    # This is row 225's blocker, and it also biased H4's scope estimate: that
    # estimate was measuring this bug rather than a real limit.
    @struct_module """
    defmodule PointT35 do
      defstruct xs: []

      # The self-reference. If the rename moves only the `defmodule` header,
      # this still says `PointT35`, which no longer exists — the module does not
      # compile and no struct-defining example can be checked at all.
      def wrap(xs), do: %PointT35{xs: xs}

      def empty?(xs), do: length(xs) == 0
    end
    """

    test "a self-referencing struct literal survives the rename" do
      assert :ok =
               assert_equivalent_module(@struct_module,
                 rule: NoLengthComparisonForEmpty,
                 call: {:empty?, 1},
                 inputs: [[], [1], [1, 2]]
               )
    end

    test "a short alias shadowing the fixture name remains external" do
      source = """
      defmodule Example do
        alias Credence.BehaviourEquivalenceSelfTest.ExternalExample, as: Example
        def run(value), do: Example.run(value)
        def flagged(value), do: length(value) == 0
      end
      """

      assert :ok =
               assert_equivalent_module(source,
                 rule: NoLengthComparisonForEmpty,
                 call: {:run, 1},
                 inputs: [{self(), 1}, {self(), 2}, {self(), 3}]
               )

      for value <- 1..3 do
        assert_receive {:external_example_called, ^value}
        assert_receive {:external_example_called, ^value}
      end
    end

    test "top-level fixture execution is isolated" do
      source = """
      defmodule BehaviourEquivalenceBoundedFixture do
        exit(:behaviour_equivalence_fixture_exit)
        def run(value), do: value
        def flagged(value), do: length(value) == 0
      end
      """

      assert_raise CompileError, fn ->
        assert_equivalent_module(source,
          rule: NoLengthComparisonForEmpty,
          call: {:run, 1},
          inputs: [[], [1], [1, 2]]
        )
      end
    end
  end

  # ── Stacktrace normalisation (docs/22 T3.4c, ledger H-C) ─────────────
  #
  # Outcomes are compared with strict `===`, so a term carrying a stacktrace is
  # uncomparable to itself: the before and after are different code, so the
  # frames differ by line and often by function. Row 33 was marked DIVERGES for
  # the one thing that could never have matched.

  describe "normalize_traces/1" do
    @frames [
      {Foo, :bar, 1, [file: ~c"a.ex", line: 3]},
      {Baz, :qux, 2, [file: ~c"b.ex", line: 9]}
    ]

    test "a bare stacktrace collapses" do
      assert Credence.BehaviourEquivalence.normalize_traces(@frames) == :__stacktrace__
    end

    # A trace arrives unlabelled inside an exit reason as often as anywhere
    # nameable, which is why the check is shape-based rather than key-based.
    test "a stacktrace nested in an exit reason collapses" do
      assert Credence.BehaviourEquivalence.normalize_traces({:badarg, @frames}) ==
               {:badarg, :__stacktrace__}
    end

    test "and one nested in a map" do
      assert Credence.BehaviourEquivalence.normalize_traces(%{err: {:x, @frames}}) ==
               %{err: {:x, :__stacktrace__}}
    end

    # The controls. A shape-based check is exactly the kind that over-matches,
    # and collapsing real data into `:__stacktrace__` would make two genuinely
    # different results compare equal — a false EQUIVALENT, which is worse than
    # the false DIVERGES this fixes.
    test "CONTROL: ordinary lists and keyword lists are untouched" do
      assert Credence.BehaviourEquivalence.normalize_traces([1, 2, 3]) == [1, 2, 3]
      assert Credence.BehaviourEquivalence.normalize_traces(a: 1, b: 2) == [a: 1, b: 2]
    end

    test "CONTROL: a list of ordinary 4-tuples is not a stacktrace" do
      ordinary_data = [{Foo, :bar, 1, :left}]

      assert Credence.BehaviourEquivalence.normalize_traces(ordinary_data) == ordinary_data
    end

    test "CONTROL: a struct is left alone" do
      assert Credence.BehaviourEquivalence.normalize_traces(~D[2024-01-01]) == ~D[2024-01-01]
    end

    # THE WIRING, not just the function. The unit tests above call
    # `normalize_traces/1` directly and stay green even with it unwired from
    # `run_outcome/2` — which is the shape of a control that proves nothing.
    # These go through `eval_outcome/1`, the path the comparison actually uses.
    test "successful frame-shaped user values remain distinct THROUGH eval_outcome" do
      other_frames =
        List.update_at(@frames, 0, fn {mod, fun, arity, location} ->
          {mod, fun, arity, Keyword.put(location, :line, 4)}
        end)

      assert Credence.BehaviourEquivalence.eval_outcome(fn -> {:trace, @frames} end) ==
               {:ok, {:trace, @frames}}

      refute Credence.BehaviourEquivalence.eval_outcome(fn -> @frames end) ===
               Credence.BehaviourEquivalence.eval_outcome(fn -> other_frames end)
    end

    test "and one inside an exit reason is too" do
      assert Credence.BehaviourEquivalence.eval_outcome(fn -> exit({:boom, @frames}) end) ==
               {:exit, {:boom, :__stacktrace__}}
    end

    test "CONTROL: an empty list is not a stacktrace" do
      assert Credence.BehaviourEquivalence.normalize_traces([]) == []
    end
  end
end
