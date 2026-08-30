defmodule Credence.SelfCorruptionTest do
  @moduledoc """
  The self-corruption gate, and the frozen ledger of the Syntax rules that were
  already rewriting their own source when it was adopted (2026-07-28).

  ## What it runs

  Every live Syntax rule's `fix/1`, over that rule's own `.ex` file. A rule that
  changes a byte of its own source has rewritten prose: a moduledoc heredoc, a
  `#` comment, or a string in its own code. The mechanism and its justification
  are in `Credence.SelfCorruption`'s moduledoc — the short version is that a
  rule's own file is the only adversarial input nobody had to author, because
  the Rule Standard *requires* its moduledoc to contain the exact byte sequences
  the rule rewrites.

  ## Why this gate exists at all

  docs/22 Part I §2 draws one conclusion from the evolution's gate-gap tally:
  where a real oracle existed, the failure class vanished from the reject pile;
  where none existed, it accumulated. "Build the oracle, kill the class." The
  byte-scope class (docs/16 §3, the 4.6a family: *a fix's blast radius needs its
  own oracle*) had two oracles — the corpus fix-safety scan and the fix-output
  re-parse. Neither can see this defect. Corrupting a string literal produces
  output that parses, compiles, and passes every equality assertion in a test
  file; the corpus cannot supply the input because real-world Elixir does not
  document Python operators in its moduledocs.

  So the class stayed invisible through review. `FixDivRem` was read, converted
  to `Credence.SourceMask`, given literal-safety tests, changelogged and shipped
  — and still rewrote its own moduledoc, because `analyze/1` masked the whole
  file while `fix/1` masked each line alone. This oracle found it in one run.

  ## What a hit is, and is not

  A hit is a defect: the rule edited bytes that are not code. A **clean** result
  is much weaker evidence — it says this rule's own file does not happen to trip
  it, not that the rule is literal-aware. `SourceMask` is the repair; passing
  here is not proof of it.

  ## The ledger, and why it is not a wall

  11 of 45 Syntax rules were corrupting their own source when this gate was
  adopted, one of them (`no_else_if`) on 226 lines. Failing all 11 on day one is
  the mistake docs/19 §2 row A already made once — a gate nobody can get green
  teaches people to disable it. So the 11 were frozen with their line counts —
  **and the ledger is now empty; all 11 are paid down.** The ratchet did what it
  was built to do, and the gate asserts three things:

    * a rule not on the ledger may not corrupt its own source at all — a new
      rule cannot land in this class, which is the point;
    * a ledgered rule may not corrupt **more** lines than its frozen ceiling —
      the debt cannot grow quietly under an entry that is already red;
    * a ledgered rule that stops corrupting must leave the ledger — so a paydown
      is permanent and can never silently regress.

  The line count is the ratchet dial, and it is deliberately a *ceiling* rather
  than an equality: a partial repair that takes `fix_do_block_fusion` from 6
  lines to 2 should be allowed to land without also being required to finish the
  job in the same commit.

  Paydown is docs/22 **T3.10**, in ledger order — which is descending line
  count, because the count is a fair proxy for how little the rule knows about
  literals.

  All eleven are paid down, and they needed *eight* different repairs — see the
  note under `@self_corrupting` and docs/22 T3.10/T3.10a. That is the lesson
  this ledger actually taught: a hit says the rule edited bytes that are not
  code, and nothing more. It does not say the repair is `SourceMask`. Assuming it
  does produces either a masked rule that is still wrong, or — worse, and this
  nearly happened to `no_doc_with_do_block` — a rule whose pattern keys on the
  very delimiters masking blanks, which then matches nothing at all and retires
  itself while every test stays green. One was not a masking bug at all:
  `fix_malformed_spec` was a rule that could never fire, and converting it would
  have been polish on a corpse.

  Even inside the six that *were* masking bugs the mechanism differed: one had to
  keep its rewrite reading the raw line because it rebuilds rather than splices,
  one had to thread the shadow through a five-stage cascade, and one turned out
  to have a second, unrelated defect underneath — a right-hand side that ran to
  end of line and swallowed trailing comments into the expression, emitting
  source that did not parse.

  And the last one was not repaired at all — it was **retired**. `no_else_if`'s
  entry was held open deliberately after the others closed, because masking its
  trigger would have cleared the entry while leaving the rule turning *valid,
  parsing* nested-`if` source into output that does not parse. The entry was the
  only thing flagging that. It closed when the rule's hardened sibling was widened
  to cover the `else if` spelling behind a terminator count and `no_else_if` was
  deleted into it (docs/22 T3.10a) — which is the strongest form this ledger's
  lesson takes: **the repair a hit calls for is sometimes not to the rule.**
  """
  use ExUnit.Case, async: true

  alias Credence.SelfCorruption

  # Rules already rewriting their own source when this gate was adopted
  # (2026-07-28). Frozen debt, not approval: the value is the number of lines of
  # its own file the rule rewrote on that day, and it is a CEILING. This map may
  # only shrink — in entries or in values. See "The ledger" above.
  #
  # Ordered by line count, which is *usually* the paydown order: the count is a
  # proxy for how little the rule knows about literals.
  #
  # EMPTY as of 2026-07-28 — every rule on the adoption-day ledger is paid down.
  # It may gain entries only by a deliberate re-freeze; the gate below treats any
  # rule not named here as forbidden to corrupt its own source at all, which is
  # now every Syntax rule in the tree.
  #
  # The last entry to leave was `no_else_if`, and it did not leave by being
  # converted. Masking its trigger would have cleared the entry while leaving the
  # rule turning *valid, parsing* nested-`if` source into output that does not
  # parse — the entry was the only flag on that, so it was held open on purpose
  # (docs/22 T3.10a) until its hardened sibling `FixElsifInIfChain` was widened to
  # cover the `else if` spelling behind a terminator-count discriminator. The rule
  # was then retired into it. A ledger entry is allowed to be load-bearing.
  @self_corrupting %{}

  # Paid down since adoption, kept here as the record of what the ratchet has
  # actually bought — and of the fact that the repair is not one repair:
  #
  #   fix_truncated_binary_close (4)  `SourceMask`, the family default. A bare
  #                                   literal pattern with no guard of any kind.
  #   prefer_cond_do_keyword (1)      NOT masking. Its parse gate proved the
  #                                   RESULT parses, not that the replacement
  #                                   repaired anything, so on already-parsing
  #                                   source every candidate qualified and the
  #                                   first occurrence won wherever it sat. It
  #                                   now declines source that parses, which is a
  #                                   no-op in a phase that only runs on source
  #                                   that does not.
  #   no_doc_with_do_block (1)        NOT the shadow either. Its pattern keys on
  #                                   the `"` quotes of `@doc "..."`, and masking
  #                                   blanks a literal's quotes along with its
  #                                   body — matching the shadow would have
  #                                   matched nothing at all, retiring the rule
  #                                   rather than fixing it. It matches the raw
  #                                   line and asks `SourceMask.self_contained?/2`
  #                                   whether the line is inside a multi-line
  #                                   literal.
  #   fix_malformed_spec (1)          NOT a repair at all — the rule was DEAD.
  #                                   `@spec f(a :: b)` parses, so the Syntax
  #                                   phase never ran on it (T1 had it ledgered
  #                                   `:dead`). It failed to *compile*, though,
  #                                   with a diagnostic nothing claimed, so it is
  #                                   re-homed to `Credence.Semantic` and off
  #                                   this ledger by leaving the phase. docs/22
  #                                   T3.8.
  #   prefer_spec_arrow_operator (1)  `SourceMask`, decision-only. This rule
  #                                   REBUILDS the line from its parts rather
  #                                   than splicing byte ranges, so the shadow
  #                                   answers "is this line code?" and the
  #                                   rewrite reads the real line. Masking the
  #                                   rebuild would have emitted blanked
  #                                   literals.
  #   fix_assignment_dot_syntax (2)   `SourceMask`, the family default — and it
  #                                   retired a hand-written whole-line `#`
  #                                   guard that the shadow strictly subsumes.
  #   fix_stale_access_modifier (3)   `SourceMask`, the family default.
  #   no_fn_with_capture (4)          `SourceMask`, replacing a `#`-only guard
  #                                   whose own comment said rewriting non-code
  #                                   "would corrupt" — the author had the right
  #                                   model and the wrong reach. Knowing about
  #                                   the class is not being guarded against it.
  #   fix_python_augmented_assignment `SourceMask`, PLUS a second defect the
  #     (4)                           conversion exposed: the right-hand side ran
  #                                   to end of line, so `count += 1  # note`
  #                                   became `count = count + (1  # note)` and
  #                                   did not parse. The shadow settles it — a
  #                                   comment is blanked to the line's end, and
  #                                   the raw byte at the run's start separates a
  #                                   comment from a trailing string.
  #   fix_do_block_fusion (6)         `SourceMask`, threaded. Five stages that
  #                                   feed each other and change byte length, so
  #                                   neither the splice-once idiom nor
  #                                   re-masking between stages is available. The
  #                                   `{line, shadow}` pair is carried through
  #                                   and both receive the identical splice.

  setup_all do
    entries = SelfCorruption.scan()
    {:ok, entries: entries, counts: SelfCorruption.counts(entries)}
  end

  describe "the gate cannot pass vacuously" do
    test "the scan sees every live Syntax rule", %{entries: entries} do
      live = length(Credence.Syntax.default_rules())

      assert length(entries) == live,
             "the scan read #{length(entries)} rules but Credence.Syntax.default_rules/0 has " <>
               "#{live}. Every check below is over the scanned set, so a scan that silently " <>
               "covers fewer rules than exist passes while saying nothing."
    end

    test "every rule's source file was actually read", %{entries: entries} do
      unreadable = for e <- entries, not File.exists?(e.path), do: e.name

      assert unreadable == [],
             "no source file at the conventional path for: #{inspect(unreadable)}. A rule whose " <>
               "file cannot be read has nothing to corrupt and would pass silently."
    end

    # The ledger is empty as of 2026-07-28, so this can no longer be "some rule
    # still corrupts". That assertion was the right one while there was debt and
    # is worthless without it — the whole point of paying it down is that it
    # reaches zero, at which moment "nobody corrupts" and "the differ stopped
    # working" become the same observation from outside.
    #
    # So the vacuity check moves from the *result* to the *machinery*: hand the
    # oracle a rule that certainly rewrites what it is given and it must report
    # the change, and hand it one that certainly does not and it must report
    # none. GREEN-0 and its perturbation, in one pair.
    defmodule AlwaysRewritesItsInput do
      @moduledoc false
      use Credence.Syntax.Rule

      @impl true
      def analyze(_source), do: []

      @impl true
      def fix(source), do: String.replace(source, "defmodule", "defmodulex")
    end

    defmodule NeverTouchesAnything do
      @moduledoc false
      use Credence.Syntax.Rule

      @impl true
      def analyze(_source), do: []

      @impl true
      def fix(source), do: source
    end

    @probe_source "lib/syntax/fix_python_modulo.ex"

    test "the oracle reports a change when there is one — positive control" do
      source = File.read!(@probe_source)

      assert Credence.SelfCorruption.corrupted_lines(AlwaysRewritesItsInput, source) > 0,
             """

             The oracle read a rule that rewrites every `defmodule` it is handed and reported
             ZERO changed lines. The detection itself is broken, which means every green result
             above — including an empty ledger — means nothing.

             Check `Credence.SelfCorruption.corrupted_lines/2` and the differ under it.
             """
    end

    test "and reports none when there is none — GREEN-0" do
      source = File.read!(@probe_source)

      assert Credence.SelfCorruption.corrupted_lines(NeverTouchesAnything, source) == 0,
             "the oracle reported changes for a rule whose `fix/1` returns its input unchanged; " <>
               "it is flagging something other than the rule's edits."
    end

    test "a rule whose fix/1 raises is a hit, not a skip" do
      # The third way the oracle could go quiet: `apply_fix/2` rescues, so a
      # raising rule must surface as damage rather than as a clean result.
      defmodule RaisesOnEverything do
        @moduledoc false
        use Credence.Syntax.Rule

        @impl true
        def analyze(_source), do: []

        @impl true
        def fix(_source), do: raise("boom")
      end

      assert Credence.SelfCorruption.corrupted_lines(RaisesOnEverything, "x = 1\n") > 0
    end
  end

  describe "the ledger" do
    test "names only live Syntax rules" do
      live =
        Credence.Syntax.default_rules()
        |> Enum.map(&Credence.RuleName.from_module(&1).snake)
        |> MapSet.new()

      stale =
        @self_corrupting |> Map.keys() |> Enum.reject(&MapSet.member?(live, &1)) |> Enum.sort()

      assert stale == [],
             "@self_corrupting names rules that no longer exist: #{inspect(stale)}. Delete them."
    end

    test "every ceiling is a positive line count" do
      bad = for {name, n} <- @self_corrupting, not (is_integer(n) and n > 0), do: {name, n}

      assert bad == [],
             "a ceiling of 0 or less is not debt, it is a rule that belongs off the ledger: " <>
               "#{inspect(bad)}"
    end
  end

  describe "the gate" do
    test "no rule rewrites its own source except the frozen ledger", %{
      entries: entries,
      counts: counts
    } do
      new =
        counts |> Map.keys() |> Enum.reject(&Map.has_key?(@self_corrupting, &1)) |> Enum.sort()

      hits = for e <- entries, e.name in new, do: SelfCorruption.render(e)

      assert new == [],
             """

             #{length(new)} Syntax rule(s) rewrote their own source file:

             #{Enum.join(hits, "\n\n")}

             Every line above is a byte the rule changed inside a moduledoc heredoc, a `#` comment
             or a string literal — prose, not code. The output still parses and still compiles, so
             nothing downstream will catch it: the program just does something its author did not
             write. This is the docs/16 §3 blast-radius family.

             The repair is `Credence.SourceMask`: match a same-length shadow in which literals,
             sigils, heredocs, charlists and comments are blanked, then splice the matched byte
             ranges into the real line. `lib/syntax/fix_python_modulo.ex` is the reference
             conversion and `lib/syntax/fix_python_floor_div.ex` is the one that also merges two
             patterns in a single pass.

             Two traps worth knowing before you start:

               * mask the WHOLE FILE, never a line on its own. Heredoc and multi-line-string state
                 crosses lines, so a heredoc body masked alone reads as pure code — that is exactly
                 the bug this gate found in `FixDivRem`, which was already "converted";
               * make `analyze` and `fix` read the same shadow. If only one is masked they disagree,
                 and the rule fixes what it never reported.

             Adding it to @self_corrupting here is NOT one of the options. That ledger is frozen
             debt from 2026-07-28 and only shrinks.
             """
    end

    test "no ledgered rule corrupts more lines than its frozen ceiling", %{counts: counts} do
      grown =
        for {name, ceiling} <- @self_corrupting,
            now = Map.get(counts, name, 0),
            now > ceiling,
            do: "    #{name}: #{ceiling} -> #{now}  (+#{now - ceiling})"

      assert grown == [],
             """

             #{length(grown)} ledgered rule(s) now rewrite MORE of their own source than when the
             ledger was frozen:

             #{Enum.join(grown, "\n")}

             The ledger is a ceiling, not a licence. An entry already being red does not make it a
             place to put new damage — that is how a ratchet turns back into a wall.
             """
    end

    test "a rule that stopped corrupting has left the ledger", %{counts: counts} do
      graduated =
        @self_corrupting
        |> Map.keys()
        |> Enum.reject(&Map.has_key?(counts, &1))
        |> Enum.sort()

      assert graduated == [],
             """

             #{length(graduated)} rule(s) are on the @self_corrupting ledger but no longer rewrite
             their own source:

             #{Enum.map_join(graduated, "\n", &"    #{&1}")}

             Remove them from @self_corrupting in this file. That is what makes the ledger shrink
             and the paydown permanent — off the ledger, the rule can never go back to corrupting
             without a deliberate re-freeze.
             """
    end
  end
end
