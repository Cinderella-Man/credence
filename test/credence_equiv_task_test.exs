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
end
