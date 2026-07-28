defmodule Credence.Mutation.SweepTest do
  use ExUnit.Case, async: true

  alias Credence.Mutation.Sweep

  @moduledoc """
  docs/22 T2.4 — the scoring and the baseline guard.

  The sweep itself spawns one OS process per mutant and runs real test files, so
  what is unit-tested here is the arithmetic every reported number passes
  through, plus the guard that decides whether a subject is scorable at all.
  """

  describe "kill_rate/1" do
    test "killed over everything that ran" do
      assert Sweep.kill_rate(%{killed: 3, survived: 1, timeout: 0, invalid: 0, error: 0}) == 0.75
    end

    # A timeout counts as KILLED. A mutant that hangs the triplet has changed
    # behaviour observably — the triplet noticed, just slowly — and scoring it as
    # a survivor would punish a rule for catching something.
    test "a timeout counts as killed" do
      assert Sweep.kill_rate(%{killed: 1, survived: 0, timeout: 1, invalid: 0, error: 0}) == 1.0
    end

    # Invalid mutants (source that no longer compiles) and errors are NOT in the
    # denominator: they were never a behaviour question, so including them would
    # let a generator bug move a rule's score.
    test "invalid and error are excluded from the denominator" do
      assert Sweep.kill_rate(%{killed: 1, survived: 1, timeout: 0, invalid: 8, error: 4}) == 0.5
    end

    # nil, not 0.0 or 1.0. Both of those are claims about tightness; "nothing
    # scorable ran" is the absence of a claim, and a 0.0 in a summary table would
    # read as a rule with a uselessly loose triplet.
    test "nothing scorable is nil, not a score" do
      refute Sweep.kill_rate(%{killed: 0, survived: 0, timeout: 0, invalid: 5, error: 0})
    end
  end

  describe "the baseline is not optional" do
    @tag :tmp_dir
    test "CONTROL: a subject whose own tests are red is discarded, not scored", %{tmp_dir: dir} do
      # A red baseline kills every mutant for the wrong reason — the triplet was
      # already failing, so every mutant "dies" and the rule scores a perfect
      # 1.0. That is the single most misleading number this task could print.
      src = Path.join(dir, "rule.ex")
      test_path = Path.join(dir, "rule_test.exs")

      File.write!(src, "defmodule SweepProbe do\n  def f(a, b), do: a >= b\nend\n")

      File.write!(test_path, """
      defmodule SweepProbeTest do
        use ExUnit.Case
        test "deliberately red" do
          assert false
        end
      end
      """)

      subject = %{
        name: "sweep_probe",
        layer: :pattern,
        source_path: src,
        test_files: [test_path]
      }

      result = Sweep.run(subject, root: dir, timeout_s: 30)

      assert result.skipped == :baseline_red
      assert result.counts.killed == 0
      assert result.counts.survived == 0
      refute Sweep.kill_rate(result.counts)
    end
  end
end
