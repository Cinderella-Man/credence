defmodule Credence.EquivTaskTest do
  # `async: false`: swaps the global `Mix.shell/0` to capture task output.
  use ExUnit.Case, async: false

  @moduledoc """
  T3.3 / C2.4 — `mix credence.equiv` must never answer EQUIVALENT from having
  compared nothing.

  `Enum.all?/2` over an empty list is `true`, so an empty battery produced the
  task's *strongest* verdict. That was not a corner case: the default battery is
  empty for **every multi-var snippet** without `--dim`, so an entire class of
  rewrite reported EQUIVALENT by default.
  """

  setup do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(shell) end)
    :ok
  end

  defp run(dir, before_src, after_src, extra) do
    b = Path.join(dir, "before.exs")
    a = Path.join(dir, "after.exs")
    File.write!(b, before_src)
    File.write!(a, after_src)

    Mix.Tasks.Credence.Equiv.run(["--before", b, "--after", a] ++ extra)

    receive do
      {:mix_shell, :info, [msg]} -> msg
    after
      0 -> flunk("task printed nothing")
    end
  end

  describe "the vacuous verdicts (C2.4)" do
    @tag :tmp_dir
    test "a multi-var snippet with no --dim is SKIPPED, not EQUIVALENT", %{tmp_dir: dir} do
      # The default battery is empty for two vars, so nothing is compared. These
      # two expressions are not even equivalent — `a - b` vs `b - a` — which is
      # the point: the old code called them EQUIVALENT.
      out = run(dir, "a - b", "b - a", ["--vars", "a,b"])

      assert out =~ "SKIPPED no_admitted_inputs"
      refute out =~ "EQUIVALENT"
    end

    @tag :tmp_dir
    test "every input raising on both sides is SKIPPED, not EQUIVALENT", %{tmp_dir: dir} do
      # String inputs against list-only code: `length/1` raises ArgumentError on
      # every one, both sides identically. `ob === oa` holds on every pair, so
      # this reported EQUIVALENT while never once producing a value to compare.
      out =
        run(dir, "length(s)", "length(s) + 0", ["--vars", "s", "--dim", "unicode_strings"])

      assert out =~ "SKIPPED all_raised"
      refute out =~ "EQUIVALENT"
    end

    @tag :tmp_dir
    test "CONTROL: differing exception classes on every input stay DIVERGES", %{tmp_dir: dir} do
      # The narrowing that keeps the clause above honest. Both sides raise on
      # every input, but with different classes — a real behaviour change, which
      # a blanket "everything raised" rule would have swallowed as SKIPPED.
      out = run(dir, "length(s)", "Enum.count(s)", ["--vars", "s", "--dim", "unicode_strings"])

      assert out =~ "DIVERGES"
      refute out =~ "SKIPPED"
    end
  end

  describe "the real verdicts still work (GREEN-0)" do
    @tag :tmp_dir
    test "an equivalent rewrite is still EQUIVALENT", %{tmp_dir: dir} do
      out = run(dir, "Enum.count(s)", "length(s)", ["--vars", "s", "--dim", "term_lists"])

      assert out =~ "EQUIVALENT"
    end

    @tag :tmp_dir
    test "a diverging rewrite is still DIVERGES", %{tmp_dir: dir} do
      out = run(dir, "Enum.count(s)", "Enum.count(s) + 1", ["--vars", "s", "--dim", "term_lists"])

      assert out =~ "DIVERGES"
    end
  end

  # ── T3.4 (a) and (b): the two probe defects behind 11 diverged re-queues ──
  #
  # Escalation ledger H-A and H-B. Ten `behaviour_diverged` rows sat at
  # `before_raised 44/44, after_ok 0/44` — the repairs were fine; the battery
  # had no struct or MapSet for a struct-shaped repair to succeed on, so a
  # MISSING INPUT TYPE read exactly like a broken fix. An eleventh (row 185)
  # died because `repair?/1` demanded the before raise on EVERY input, and one
  # input short-circuited the hallucinated call away.

  describe "REPAIR is reachable for struct-shaped and partially-raising repairs" do
    @tag :tmp_dir
    test "a repair whose fixed form needs a struct is REPAIR, not DIVERGES", %{tmp_dir: dir} do
      # `Date.to_tuple/1` does not exist; `Date.to_erl/1` does. Before the
      # struct dimension existed the AFTER had no date to succeed on, so this
      # verdict was DIVERGES and the row was auto-killed.
      out = run(dir, "Date.to_tuple(d)", "Date.to_erl(d)", ["--vars", "d"])

      assert out =~ "REPAIR"
      refute out =~ "DIVERGES"
    end

    @tag :tmp_dir
    test "a before that raises on all but a short-circuiting input is REPAIR (H-B)", %{
      tmp_dir: dir
    } do
      # `Enum.all?([], &DateTime.valid?/1)` is `true` WITHOUT calling the
      # hallucinated predicate, so the before does not raise on `[]`. Demanding
      # it raise on every input killed the whole verdict over one input the
      # repair never reaches.
      out =
        run(
          dir,
          "Enum.all?(list, &DateTime.valid?/1)",
          "Enum.all?(list, &match?(%DateTime{}, &1))",
          ["--vars", "list"]
        )

      assert out =~ "REPAIR"
    end

    # THE MANDATORY CONTROL (docs/22 T3.4, escalation ledger row 105). The
    # proposed fix rewrites `File.stream!/1`, which exists, to `File.stream/1`,
    # which does not — so the AFTER raises on every input. Neither the widened
    # battery nor the tolerant `repair?/1` may rescue it: the `after succeeded
    # on >= 1` clause is what keeps a broken repair broken, and a probe change
    # that flips this row has widened the wrong thing.
    @tag :tmp_dir
    test "CONTROL: row 105 stays DIVERGES — a repair that is itself broken", %{tmp_dir: dir} do
      out = run(dir, "File.stream!(path)", "File.stream(path)", ["--vars", "path"])

      assert out =~ "DIVERGES"
      refute out =~ "REPAIR"
    end

    # The other direction: tolerance must not admit a real behaviour change.
    # Neither side raises here and the answers differ, so `ob === oa` is false
    # on every input and the pair can never be a repair.
    @tag :tmp_dir
    test "CONTROL: a plain wrong answer is still DIVERGES", %{tmp_dir: dir} do
      out = run(dir, "Enum.count(list)", "Enum.count(list) + 1", ["--vars", "list"])

      assert out =~ "DIVERGES"
      refute out =~ "REPAIR"
    end
  end
end
