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
  teaches people to disable it. So the 11 are frozen with their line counts, and
  the gate asserts three things:

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

  Two are paid down so far, and they needed *different* repairs — see the note
  under `@self_corrupting`. That is the useful early lesson from this ledger: a
  hit says the rule edited bytes that are not code, and nothing more. It does not
  say the repair is `SourceMask`, and assuming it does will produce a masked rule
  that is still wrong.
  """
  use ExUnit.Case, async: true

  alias Credence.SelfCorruption

  # Rules already rewriting their own source when this gate was adopted
  # (2026-07-28). Frozen debt, not approval: the value is the number of lines of
  # its own file the rule rewrote on that day, and it is a CEILING. This map may
  # only shrink — in entries or in values. See "The ledger" above.
  #
  # Ordered by line count, which is the paydown order: the count is a proxy for
  # how little the rule knows about literals. `no_else_if` rewrites most of its
  # own file because it is a multi-line block rewrite with neither a comment
  # guard nor heredoc tracking — its sibling `fix_elsif_in_if_chain` has both.
  @self_corrupting %{
    "no_else_if" => 226,
    "fix_do_block_fusion" => 6,
    "fix_python_augmented_assignment" => 4,
    "no_fn_with_capture" => 4,
    "fix_stale_access_modifier" => 3,
    "fix_assignment_dot_syntax" => 2,
    "fix_malformed_spec" => 1,
    "prefer_spec_arrow_operator" => 1
  }

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

    test "the oracle still fires — the ledger is not green by accident", %{counts: counts} do
      refute counts == %{},
             """

             ZERO Syntax rules rewrite their own source. That would be excellent news, and it is
             almost certainly false: #{map_size(@self_corrupting)} did on 2026-07-28 and this
             gate's own ledger says so.

             The likely cause is that the oracle stopped running, not that the class was fixed —
             `fix/1` raising and being swallowed, the rule list coming back empty, or the source
             paths no longer resolving. Check `Credence.SelfCorruption.scan/1` before celebrating.

             If the class really was paid down, empty @self_corrupting first, in the commit that
             did it.
             """
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
