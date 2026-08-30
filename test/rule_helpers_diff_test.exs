defmodule Credence.RuleHelpersDiffTest do
  use ExUnit.Case, async: true

  alias Credence.RuleHelpers

  @moduledoc """
  docs/22 T3.6 — `diff_lines/2` paired the two files by INDEX.

  A single inserted line shifted everything after it, so the whole file rendered
  as changed. That fabricated a "catastrophic replacement" bug report out of a
  correct module reorder (escalation ledger row 181), and it is what pushed the
  `APPLIED_RULES:` line — printed last — past Elixir's 8096-byte Logger cap
  (row 120).
  """

  describe "an insertion is one added line, not a rewrite" do
    test "inserting a line reports exactly that line" do
      before = "a\nb\nc\n"
      after_fix = "a\nNEW\nb\nc\n"

      assert RuleHelpers.diff_lines(before, after_fix) == [{:added, 2, "NEW"}]
    end

    test "deleting a line reports exactly that line" do
      assert RuleHelpers.diff_lines("a\nb\nc\n", "a\nc\n") == [{:removed, 2, "b"}]
    end

    test "a changed line is one removal and one addition" do
      assert RuleHelpers.diff_lines("a\nb\nc\n", "a\nB\nc\n") == [
               {:removed, 2, "b"},
               {:added, 2, "B"}
             ]
    end

    test "identical sources produce no changes" do
      assert RuleHelpers.diff_lines("a\nb\n", "a\nb\n") == []
    end
  end

  # The ledger's actual case, at a realistic size. A small block moves inside a
  # large file; positional pairing renders EVERY line from the move onward as
  # changed, which is how a correct reorder was reported as catastrophic.
  test "a small move inside a large file reports the move, not everything after it" do
    body = Enum.map_join(1..40, "\n", &"  def f#{&1}, do: #{&1}")

    before = "defmodule M do\n  @moduledoc \"x\"\n" <> body <> "\nend\n"
    # Move the moduledoc down two lines — everything after it shifts by one.
    after_fix = "defmodule M do\n" <> body <> "\n  @moduledoc \"x\"\nend\n"

    changes = RuleHelpers.diff_lines(before, after_fix)
    total_lines = before |> String.split("\n") |> length()

    # Positional pairing produced ~2 entries per line from the shift onward.
    # A real diff reports the moved line: one removal, one addition.
    assert length(changes) <= 4,
           "a one-line move rendered as #{length(changes)} changes in a #{total_lines}-line file"
  end

  describe "line numbers index the right side" do
    test "removals index the BEFORE file and additions the AFTER file" do
      # `b` is dropped and two lines are appended: the removal must name line 2
      # of before, the additions lines 3 and 4 of after.
      assert RuleHelpers.diff_lines("a\nb\nc\n", "a\nc\nX\nY\n") == [
               {:removed, 2, "b"},
               {:added, 3, "X"},
               {:added, 4, "Y"}
             ]
    end
  end
end
