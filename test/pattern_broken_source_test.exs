defmodule Credence.PatternBrokenSourceTest do
  @moduledoc """
  The Pattern round on source that parses but does not compile.

  It used to skip all 156 rules for such a file. The measurement that ended
  that: **625 of 1,724 Pattern test fixtures parse but do not compile, and 292
  of those have at least one Pattern rule firing that never ran.** A single
  undefined helper — `&even?/1` with nothing defining `even?` — was enough, and
  that is what LLM-generated code looks like before the rest of the module
  exists, which is the input Credence was built for.

  The replacement oracle is relative rather than absolute: a fix is accepted
  when its compile errors are a subset of the ones already there. On input that
  compiles the baseline is empty, so the check is byte-for-byte the old
  `compiles?/1` — that equivalence is what makes the change safe, and it is
  asserted below rather than asserted-by-argument.
  """
  use ExUnit.Case, async: false

  alias Credence.RuleHelpers

  # `&even?/1` is never defined, so this file cannot compile. It parses fine,
  # and `Enum.at(Stream.filter(...), 0)` is squarely `NoFilterThenFirst`.
  @broken """
  defmodule PbsBroken do
    def first_even(nums), do: Enum.at(Stream.filter(nums, &even?/1), 0)
  end
  """

  @clean """
  defmodule PbsClean do
    def first_even(nums), do: Enum.at(Stream.filter(nums, &(rem(&1, 2) == 0)), 0)
  end
  """

  describe "a file that parses but does not compile is still fixed" do
    test "the pre-existing error is real, not assumed" do
      refute RuleHelpers.compiles?(@broken)
      assert {:ok, _} = Sourceror.parse_string(@broken)
    end

    test "the Pattern round runs and applies the repair" do
      result = Credence.fix(@broken)

      assert result.code =~ "Enum.find(nums, &even?/1)"
      assert {Credence.Pattern.NoFilterThenFirst, 1} in result.applied_rules
    end

    test "the repair does not silently resolve the pre-existing error" do
      # The undefined function is still undefined afterwards: the Pattern round
      # repaired the idiom it understands and left the rest of the file alone.
      # A fix that made this compile would mean it had invented a definition.
      refute RuleHelpers.compiles?(Credence.fix(@broken).code)
    end

    test "the same idiom in a compiling file is repaired identically" do
      assert Credence.fix(@clean).code =~ "Enum.find(nums, &(rem(&1, 2) == 0))"
    end
  end

  describe "compiles_no_worse?/2 — the oracle itself" do
    test "on a compiling source the baseline is empty and the check IS compiles?/1" do
      baseline = RuleHelpers.compile_errors(@clean)
      assert MapSet.size(baseline) == 0

      # Equivalence on the path that already worked, stated as an assertion
      # rather than as an argument: for an empty baseline the two must agree on
      # every input, so a future change to either cannot silently diverge.
      for candidate <- [@clean, @broken, "defmodule PbsOk do\n  def f, do: :ok\nend\n"] do
        assert RuleHelpers.compiles_no_worse?(candidate, baseline) ==
                 RuleHelpers.compiles?(candidate)
      end
    end

    test "an unchanged broken file is no worse than itself" do
      assert RuleHelpers.compiles_no_worse?(@broken, RuleHelpers.compile_errors(@broken))
    end

    test "a NEW error on top of an existing one is rejected" do
      baseline = RuleHelpers.compile_errors(@broken)

      worse = """
      defmodule PbsBroken do
        def first_even(nums), do: Enum.at(Stream.filter(nums, &even?/1), 0)
        def other, do: also_undefined()
      end
      """

      refute RuleHelpers.compiles_no_worse?(worse, baseline)
    end

    test "removing an error is accepted — a subset, not an equality" do
      baseline = RuleHelpers.compile_errors(@broken)
      assert RuleHelpers.compiles_no_worse?(@clean, baseline)
    end

    test "trading one error for a different one is rejected, though the count is equal" do
      baseline = RuleHelpers.compile_errors(@broken)

      swapped = """
      defmodule PbsBroken do
        def first_even(nums), do: Enum.at(Stream.filter(nums, &odd_undefined?/1), 0)
      end
      """

      refute RuleHelpers.compiles_no_worse?(swapped, baseline)
    end

    test "position is not part of the signature — the same error moved is the same error" do
      baseline = RuleHelpers.compile_errors(@broken)

      shifted = """
      defmodule PbsBroken do
        # a fix that inserts a line must not look like a regression

        def first_even(nums), do: Enum.at(Stream.filter(nums, &even?/1), 0)
      end
      """

      assert RuleHelpers.compiles_no_worse?(shifted, baseline)
    end
  end

  describe "a fix that breaks a working file is still reverted" do
    # The guarantee the old absolute oracle provided, restated for the new one.
    # Without this, "relative" could quietly mean "permissive".
    test "an empty baseline rejects anything that does not compile" do
      assert RuleHelpers.compile_errors(@clean) |> MapSet.size() == 0

      refute RuleHelpers.compiles_no_worse?(
               "defmodule PbsBad do\n  def f, do: undefined_thing()\nend\n",
               MapSet.new()
             )
    end
  end

  describe "warnings are not errors" do
    # `compiles?/1` has always accepted a file that warns, so the signature must
    # not start reverting fixes over a warning the source already had.
    test "a file that only warns has an empty error baseline" do
      warns = """
      defmodule PbsWarn do
        def f(unused_arg), do: :ok
      end
      """

      assert RuleHelpers.compiles?(warns)
      assert MapSet.size(RuleHelpers.compile_errors(warns)) == 0
    end
  end
end
