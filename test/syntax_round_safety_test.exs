defmodule Credence.SyntaxRoundSafetyTest do
  @moduledoc """
  C3. The Syntax round's two guards.

  The round is the one place where rules rewrite raw strings with no AST to keep
  them honest, and its input never parses — so its *intermediate* states are
  legitimately unparseable too. That rules out the obvious gate ("every rule's
  output must parse"): it would disable the round. What is enforced instead is:

    * per rule — the output is kept unless it is demonstrably **worse**
      (`Credence.Syntax.ProgressGuard`), and a regression is reverted and
      recorded as `{rule, :reverted}`;
    * per round — if the source still does not parse when every rule has run,
      the **original** comes back rather than a half-rewritten file, with each
      kept change downgraded to `{rule, :rolled_back}`.

  The fixture rules below are deliberately broken, one per regression the guard
  must catch, and each is paired with a case proving the guard stays out of the
  way of a real multi-rule repair.
  """
  use ExUnit.Case, async: true

  alias Credence.Issue
  alias Credence.RuleHelpers
  alias Credence.Syntax.ProgressGuard

  # ── fixture rules ─────────────────────────────────────────────────────────

  defmodule FixesTheKeywordOrder do
    @moduledoc false
    use Credence.Syntax.Rule

    @impl true
    def priority, do: 900

    @impl true
    def analyze(source) do
      if String.contains?(source, "name: 1, []"),
        do: [%Issue{rule: :fixture_keyword_order, message: "x", meta: %{line: 0}}],
        else: []
    end

    @impl true
    def fix(source), do: String.replace(source, "name: 1, []", "[], name: 1")
  end

  defmodule FixesTheInfixDiv do
    @moduledoc false
    use Credence.Syntax.Rule

    @impl true
    def priority, do: 100

    @impl true
    def analyze(source) do
      if String.contains?(source, "total div 2"),
        do: [%Issue{rule: :fixture_infix_div, message: "x", meta: %{line: 0}}],
        else: []
    end

    @impl true
    def fix(source), do: String.replace(source, "total div 2", "div(total, 2)")
  end

  # The Phase-4 corruption class, minimised: a textual rewrite that lands on a
  # line the parser had already accepted and breaks it, while the error the round
  # is actually chasing sits further down the file.
  defmodule BreaksALineTheParserHadAccepted do
    @moduledoc false
    use Credence.Syntax.Rule

    @impl true
    def priority, do: 100

    @impl true
    def analyze(_source), do: []

    @impl true
    def fix(source), do: String.replace(source, "Enum.sum(values)", "Enum.sum(values,)")
  end

  # The class the `evolution` branch rejected 7+ line-regex rules for: a rewrite
  # that walks into heredoc content and loses its terminator. The damage is
  # invisible to position alone — an unterminated heredoc is reported at its
  # *opening* line and the front end then runs to EOF, so the reported position
  # moves *forward* while the source gets strictly worse.
  defmodule ManglesAHeredocTerminator do
    @moduledoc false
    use Credence.Syntax.Rule

    @impl true
    def priority, do: 100

    @impl true
    def analyze(_source), do: []

    @impl true
    def fix(source), do: String.replace(source, ~s(  """\n\n), "\n")
  end

  # Fires on whatever it is handed, including source an earlier rule has already
  # brought back to parsing.
  defmodule BreaksWhateverItIsGiven do
    @moduledoc false
    use Credence.Syntax.Rule

    @impl true
    def priority, do: 900

    @impl true
    def analyze(_source), do: []

    @impl true
    def fix(source), do: String.replace(source, "def go", "def go(")
  end

  # Closes a heredoc that had swallowed the rest of the file. Before the fix the
  # front end ran to EOF; after it, it stops at the *earlier* fault the heredoc
  # was hiding. That is the repair, and it must not read as a retreat.
  defmodule ClosesTheRunawayHeredoc do
    @moduledoc false
    use Credence.Syntax.Rule

    @impl true
    def priority, do: 100

    @impl true
    def analyze(_source), do: []

    @impl true
    def fix(source), do: String.replace(source, ~s(  @doc """\n), ~s(  @doc """\n  """\n))
  end

  # Rewrites the line that carries the parse error and leaves it broken in a
  # different way. Inside its own edit there is nothing to compare against, so
  # this is kept — the documented boundary of the position measure.
  defmodule RewritesTheBrokenLine do
    @moduledoc false
    use Credence.Syntax.Rule

    @impl true
    def priority, do: 100

    @impl true
    def analyze(_source), do: []

    @impl true
    def fix(source), do: String.replace(source, "name: 1, []", "name: 1, [],")
  end

  # A real, partial repair: it clears one of the two faults and leaves the file
  # unparseable. Nothing about that is a regression.
  defmodule PartiallyRepairs do
    @moduledoc false
    use Credence.Syntax.Rule

    @impl true
    def priority, do: 100

    @impl true
    def analyze(_source), do: []

    @impl true
    def fix(source), do: String.replace(source, "total div 2", "div(total, 2)")
  end

  # ── fixtures ──────────────────────────────────────────────────────────────

  # Two independent faults. The parser only ever reports the first one it meets
  # (line 7), so the `div` fix on line 3 is an intermediate step that leaves the
  # source unparseable — the state the round exists to walk through.
  @two_faults """
  defmodule Sample do
    def gauss(total) do
      total div 2
    end

    def broken(x) do
      Enum.map(x, name: 1, [])
    end
  end
  """

  # Parses everywhere except line 7; line 3 is code the parser accepts.
  @sound_line_and_a_fault """
  defmodule Sample do
    def total(values) do
      Enum.sum(values)
    end

    def broken(x) do
      Enum.map(x, name: 1, [])
    end
  end
  """

  @heredoc_and_a_fault """
  defmodule Sample do
    @moduledoc \"\"\"
    Docs that a line-regex rule must not walk into.
    \"\"\"

    def broken(x) do
      Enum.map(x, name: 1, [])
    end
  end
  """

  @repairable_then_broken """
  defmodule Sample do
    def go do
      Enum.map([1], name: 1, [])
    end
  end
  """

  # A runaway heredoc hides a second fault below it: the front end consumes the
  # whole file looking for the terminator, so it stops at EOF and says nothing
  # about where the damage is. Harvested from the real corpus sweep.
  @runaway_heredoc """
  defmodule Sample do
    @doc \"\"\"
    def find_min_max(list) do
      Enum.min_max(list)
    end
  end

  [
    :key1: val1,
    :key2: val2
  ]
  """

  # `@runaway_heredoc` with the doc closed — the exact bytes both the stunt
  # double and the real `CloseUnclosedDocHeredoc` are required to produce.
  @runaway_heredoc_closed """
  defmodule Sample do
    @doc \"\"\"
    \"\"\"
    def find_min_max(list) do
      Enum.min_max(list)
    end
  end

  [
    :key1: val1,
    :key2: val2
  ]
  """

  defp parses?(source), do: match?({:ok, _}, Sourceror.parse_string(source))

  describe "per-rule progress guard — what it must NOT do" do
    test "keeps a partial repair that leaves the source unparseable" do
      {code, applied} =
        Credence.Syntax.fix_with_trace(@two_faults,
          syntax_rules: [PartiallyRepairs, FixesTheKeywordOrder]
        )

      # Both rules kept: the first one's output did not parse either, and that is
      # exactly the intermediate state the round is built to pass through.
      assert applied == [{PartiallyRepairs, 1}, {FixesTheKeywordOrder, 1}]
      assert code =~ "div(total, 2)"
      assert code =~ "Enum.map(x, [], name: 1)"
      assert parses?(code)
    end

    test "a real two-rule repair (infix div + keyword order) still completes" do
      {code, applied} = Credence.Syntax.fix_with_trace(@two_faults)

      assert code =~ "div(total, 2)"
      assert code =~ "Enum.map(x, [], name: 1)"
      assert parses?(code)

      names =
        Enum.map(applied, fn {rule, count} -> {RuleHelpers.rule_name(rule), count} end)

      assert {"FixDivRem", 1} in names
      assert {"FixKeywordBeforePositionalArgument", 1} in names
      refute Enum.any?(names, fn {_name, count} -> count in [:reverted, :rolled_back] end)
    end

    test "keeps a repair that reveals an earlier fault the front end had run past" do
      # Closing the heredoc moves the report from EOF (12:1) to the fault it was
      # hiding (10:8) — backwards by position, forwards by every other measure.
      # An EOF stop says nothing about where the damage is, so it is never
      # compared.
      {code, applied} =
        Credence.Syntax.fix_with_trace(@runaway_heredoc,
          syntax_rules: [ClosesTheRunawayHeredoc],
          syntax_partial_repairs: true
        )

      assert applied == [{ClosesTheRunawayHeredoc, 1}]
      assert code == @runaway_heredoc_closed
    end

    # The case above is what the guard must do; this one is what the *shipped*
    # rule actually does with the same source. The stunt double above only
    # models `CloseUnclosedDocHeredoc` — nothing there would notice if the real
    # rule stopped firing on this fixture, and the guard's own docs
    # (`lib/syntax/progress_guard.ex`) name this rule as where the EOF-stop
    # exclusion was learned. So pin the real rule's bytes, and pin that they are
    # the bytes the stunt double stands in for.
    test "the real CloseUnclosedDocHeredoc is the rule that repair models" do
      {code, applied} =
        Credence.Syntax.fix_with_trace(@runaway_heredoc,
          syntax_rules: [Credence.Syntax.CloseUnclosedDocHeredoc],
          syntax_partial_repairs: true
        )

      assert applied == [{Credence.Syntax.CloseUnclosedDocHeredoc, 1}]
      assert code == @runaway_heredoc_closed
      assert code == ClosesTheRunawayHeredoc.fix(@runaway_heredoc)

      # The repair is real even though the source still does not parse: the
      # front end no longer runs to EOF, it stops at the fault the heredoc hid.
      refute parses?(code)
    end

    test "keeps a rewrite of the erroring line that leaves it broken differently" do
      # The boundary of the position measure, pinned on purpose: inside the
      # region a rule rewrote there is nothing comparable on the two sides, so a
      # rewrite that lands on the erroring line is kept and the all-or-nothing
      # gate is what decides the round. This is also why the Phase-4
      # `div(def f(n), do: …)` corruption is not caught here — measured, it moved
      # the error from 2:29 to 2:32, i.e. *forward*, on the line it rewrote.
      {code, applied} =
        Credence.Syntax.fix_with_trace(@two_faults,
          syntax_rules: [RewritesTheBrokenLine],
          syntax_partial_repairs: true
        )

      assert applied == [{RewritesTheBrokenLine, 1}]
      assert code =~ "name: 1, [],"
      refute parses?(code)
    end

    test "a real repair whose reported error never moves (missing `end`) is not reverted" do
      # "missing terminator: end" is reported at the *opening* `do` on line 1, so
      # the `div` fix on line 3 cannot move it at all — and appending the missing
      # `end` moves it nowhere either. Neither is a regression.
      source = """
      defmodule Sample do
        def gauss(total) do
          total div 2
        end
      """

      {code, applied} = Credence.Syntax.fix_with_trace(source)

      assert code =~ "div(total, 2)"
      assert parses?(code)
      assert Enum.all?(applied, fn {_rule, count} -> is_integer(count) end)
    end
  end

  describe "per-rule progress guard — what it must catch" do
    test "reverts a rule that breaks a line the parser had already accepted" do
      {code, applied} =
        Credence.Syntax.fix_with_trace(@sound_line_and_a_fault,
          syntax_rules: [BreaksALineTheParserHadAccepted]
        )

      # The round's error was on line 7; the rewrite put one on line 3, above its
      # own edit's reach — the parser used to get past that line and now does not.
      assert applied == [{BreaksALineTheParserHadAccepted, :reverted}]
      assert code == @sound_line_and_a_fault
    end

    test "reverts a rule that leaves the source no longer tokenizing" do
      {code, applied} =
        Credence.Syntax.fix_with_trace(@heredoc_and_a_fault,
          syntax_rules: [ManglesAHeredocTerminator]
        )

      assert applied == [{ManglesAHeredocTerminator, :reverted}]
      assert code == @heredoc_and_a_fault
    end

    test "reverts a rule that breaks source an earlier rule had already repaired" do
      {code, applied} =
        Credence.Syntax.fix_with_trace(@repairable_then_broken,
          syntax_rules: [FixesTheKeywordOrder, BreaksWhateverItIsGiven]
        )

      assert applied == [{FixesTheKeywordOrder, 1}, {BreaksWhateverItIsGiven, :reverted}]
      assert code =~ "Enum.map([1], [], name: 1)"
      assert code =~ "def go do"
      assert parses?(code)
    end
  end

  describe "phase-level all-or-nothing" do
    test "returns the original source when the round ends unparseable" do
      {code, applied} =
        Credence.Syntax.fix_with_trace(@two_faults, syntax_rules: [PartiallyRepairs])

      assert code == @two_faults
      assert applied == [{PartiallyRepairs, :rolled_back}]
    end

    test "syntax_partial_repairs: true opts out and returns the partial rewrite" do
      {code, applied} =
        Credence.Syntax.fix_with_trace(@two_faults,
          syntax_rules: [PartiallyRepairs],
          syntax_partial_repairs: true
        )

      assert code =~ "div(total, 2)"
      assert applied == [{PartiallyRepairs, 1}]
    end

    test "a round that repaired the source commits normally" do
      {code, applied} =
        Credence.Syntax.fix_with_trace(@repairable_then_broken,
          syntax_rules: [FixesTheKeywordOrder]
        )

      assert applied == [{FixesTheKeywordOrder, 1}]
      assert parses?(code)
    end

    test "Credence.fix/2 never hands a half-rewritten Syntax result to the later rounds" do
      %{code: code} = Credence.fix(@two_faults, syntax_rules: [PartiallyRepairs])

      assert code == @two_faults
    end
  end

  describe "ProgressGuard.measure/1" do
    test "separates tokenize failure from parse failure from success" do
      assert {:parses, _, _} = ProgressGuard.measure("x = 1\n")
      assert {:parse_error, _, _} = ProgressGuard.measure("f(name: 1, [])\n")
      assert {:tokenize_error, _, _} = ProgressGuard.measure("defmodule A do\n  def a, do: 1\n")
    end

    test "reports where the front end stopped, not where the open delimiter is" do
      # `missing terminator: end` is reported at the opening `do` (1:13) but the
      # tokenizer ran to EOF — measuring the opening delimiter would make closing
      # an inner delimiter look like a regression.
      assert {:tokenize_error, 3, 1} = ProgressGuard.measure("defmodule A do\n  def a, do: 1\n")
    end

    test "an unmeasurable state is never a regression" do
      state = {:unknown, 0, 0}
      assert ProgressGuard.verdict("a", state, "b", {:parse_error, 1, 1}) == :keep
      assert ProgressGuard.verdict("a", {:parse_error, 1, 1}, "b", state) == :keep
    end
  end

  describe "analyze/2" do
    test "honours :syntax_rules" do
      assert [%Issue{rule: :fixture_keyword_order}] =
               Credence.Syntax.analyze(@two_faults, syntax_rules: [FixesTheKeywordOrder])

      assert Credence.Syntax.analyze(@two_faults, syntax_rules: [FixesTheInfixDiv]) != []
      assert Credence.Syntax.analyze("x = 1\n", syntax_rules: [FixesTheKeywordOrder]) == []
    end
  end
end
