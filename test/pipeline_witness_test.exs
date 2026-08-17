defmodule Credence.PipelineWitnessTest do
  @moduledoc """
  T1 — every rule must witness its own failure mode through the real pipeline.

  For each of the 290 rules: does any string fixture in that rule's own test
  files make that rule fire through its phase's `analyze/2`, against the full
  live rule set? See `Credence.PipelineWitness` for the mechanism and for why
  calling the phase is the same call as `Credence.analyze/2`.

  ## What this catches that nothing else did

  Every other per-rule gate is shape-based or calls the rule directly, and both
  agree with a rule that is inert in production. 86 of the 143 rules rejected at
  acceptance review died for three reasons this gate covers and the harness's
  own Gate did not: a diagnostic the compiler never emits (35), a Syntax rule
  whose target parses so the phase never runs (18), and a rule shadowed at its
  dispatch slot by a live one (33).

  It is not only a gate for new rules. Run against the surviving tree it found
  two **live shipped rules that cannot fire**, both of the historical classes:

    * `Syntax.FixMalformedSpec` — its moduledoc says "## Bad (won't parse)", but
      `@spec save!(map() :: {:ok, map()})` **parses**: `::` is an ordinary
      right-associative binary operator (`elixir_parser.yrl` `Right 60
      type_op_eol`), so `f(a :: b)` is a well-formed call argument. The Syntax
      phase only runs on source that fails to parse, so this rule is inert by
      construction — the G2 class exactly.
    * `Semantic.FixWithElseBareValue` — `match?/1` requires a message string
      that Elixir 1.20.2 does not emit.

  ## The ledger, and why it is not a wall

  Ten rules do not witness today. Each is frozen below **with the reason it
  fails**, because the reasons demand different repairs and collapsing them into
  one list would lose that. The ledger may only shrink. C13/C14 established the
  shape; this follows it.

  Note what is deliberately *not* here: `:no_fixture` and `:wrong_phase` are kept
  apart. A `:no_fixture` rule can be repaired by adding a fixture that exercises
  the failure mode the rule exists for. A `:wrong_phase` rule cannot — a fixture
  could be constructed that makes this gate green (both crypto/ets rules DO win
  their diagnostic when the offending call sits in a module attribute, verified
  by running it), but the shape the rule documents and repairs is a call in a
  `def` body, which the Semantic phase never sees because it is never evaluated
  at compile time. Adding that fixture would buy a green gate and leave the real
  defect uncovered. The honest disposition is the ledger entry plus the note
  that the rule belongs in the Pattern phase, where its `fix/2` transplants
  unchanged.
  """
  # `async: false`. This gate COMPILES every candidate fixture of every Semantic
  # and Syntax rule, and those fixtures share module names on a scale that makes
  # concurrent compilation unsafe: 413 say `defmodule M`, 304 say `Example`, 167
  # say `Solution`. The Erlang code server is global, so two async tests
  # compiling `Example` race — one deletes the module the other is mid-check on —
  # and the symptom is this gate reporting a healthy rule as DEAD.
  #
  # Observed exactly that way: `NoMapUpdateMissingKey`, whose fixtures are
  # `defmodule Example`, reported as unwitnessed in a full run and green when the
  # file was run alone. A false "this rule is dead" is the most expensive kind of
  # flake here, because the whole point of this gate is to be believed.
  #
  # Serialising is the containment, not the cure. See
  # `docs/24-improvement-research.md` §A8 for the real fix and why it was not
  # done at the same time.
  use ExUnit.Case, async: false

  # Builds an index over every rule test file and probes 290 rules; ~4 s total,
  # but it is I/O- and compile-bound in a way an ordinary unit test is not, and
  # under a full run the corpus scan competes with it.
  @moduletag timeout: :timer.minutes(10)

  alias Credence.PipelineWitness, as: Witness

  # Two rules claiming the same diagnostic, used to demonstrate that Semantic
  # dispatch really is first-match-wins. Defined here rather than in
  # `test/support` on purpose: `RuleHelpers.discover_rules/1` reads
  # `Application.spec(:credence, :modules)`, which covers `test/support` but
  # never a `_test.exs` file, so these cannot leak into the live rule set.
  defmodule ShadowingWinner do
    @moduledoc false
    use Credence.Semantic.Rule

    @impl true
    def match?(%{message: msg}) when is_binary(msg), do: String.contains?(msg, "is unused")
    def match?(_), do: false

    @impl true
    def to_issue(d), do: %Credence.Issue{rule: :shadowing_winner, message: d.message, meta: %{}}

    @impl true
    def fix(source, _), do: source
  end

  defmodule ShadowingLoser do
    @moduledoc false
    use Credence.Semantic.Rule

    @impl true
    def match?(%{message: msg}) when is_binary(msg), do: String.contains?(msg, "is unused")
    def match?(_), do: false

    @impl true
    def to_issue(d), do: %Credence.Issue{rule: :shadowing_loser, message: d.message, meta: %{}}

    @impl true
    def fix(source, _), do: source
  end

  @phases [:syntax, :semantic, :pattern]

  # ── The ledger ─────────────────────────────────────────────────────────────
  #
  # Rules that did not witness when this gate was adopted (2026-07-28). Frozen
  # debt, not approval. This list may ONLY shrink. Every entry was triaged
  # individually against the compiler and the Elixir/OTP sources, and each
  # verdict below was confirmed by executing the case, not by reading alone.
  #
  #   :dep_gated  — PAID DOWN (T5.9). The rule's diagnostic only existed when a
  #     dependency credence did not carry was present; the fixtures produced
  #     "module Plug.Conn is not loaded and could not be found" instead of the
  #     rule's target message. All four were alive in the evolution harness
  #     workspace all along, so this was a property of THIS CHECKOUT, not of the
  #     rules. Repaired by adding plug + nimble_csv as `only: :test` deps, which
  #     is the honest option — a `test/support` stub reproducing the message
  #     costs no dependency but proves less, since it witnesses the stub.
  #
  #   :no_fixture — PAID DOWN (T5.9), and it did not mean what it says. The
  #     diagnostic was real and the rule won its dispatch slot, but for
  #     `NoHallucinatedTaskTimeoutErrorStruct` no fixture COULD witness:
  #     `match?/1` accepted the expression-position message while `fix/2`
  #     repaired a pattern, which emits a different one. "No fixture" was a
  #     symptom of a rule keyed to two disjoint situations, not of nobody having
  #     written one. Keep the reason; distrust its face value.
  #
  #   :wrong_phase — PAID DOWN (T5.9). Reachable only in a source shape that is
  #     not the shape the rule documents and repairs: both rules keyed on a
  #     RUNTIME ArgumentError, which the compiler emits only when the offending
  #     call sits in a module attribute and is therefore evaluated at compile
  #     time. In a `def` body — the shape both moduledocs describe — compiling
  #     the fixture yields zero diagnostics, so the Semantic phase could not
  #     fire either rule, ever. A witnessing fixture was constructible and would
  #     have been a lie. Both re-homed to Pattern, where the shape is visible in
  #     the AST alone.
  #
  #     The move was not the transplant this file predicted. Semantic's
  #     `fix(source, diagnostic)` returns a whole new source string; Pattern's
  #     `fix_patches(ast, opts)` returns byte ranges. Porting
  #     `NoHallucinatedEtsKeytypeOption` through the AST differ put the patch on
  #     the bare option list, whose range starts one column inside the `[` while
  #     its rendering carries brackets — emitting
  #     `:ets.new(:a, [[:set, keypos: 2]])`. Pinned in that rule's fix test.
  #
  #   :dead — PAID DOWN (T3.8). The rule cannot fire at all, on this toolchain,
  #     in any shape. Both entries were repaired without deleting anything, which
  #     is the standing rule vindicated: `FixMalformedSpec` was re-homed to the
  #     Semantic phase (its target parses, so Syntax never saw it, but it fails
  #     to COMPILE with a diagnostic nothing claimed), and `FixWithElseBareValue`
  #     needed one attribute — it matched a message Elixir 1.20.2 does not emit,
  #     while its `fix/2` was correct all along.
  # EMPTY as of 2026-07-28 (T5.9 complete): every rule in all three phases
  # witnesses its own failure mode through the real pipeline. The reasons above
  # are kept as the record of what the eight entries turned out to mean — each
  # named a different defect, and none of them meant "this rule is fine".
  @ledger %{}

  @reasons [:dep_gated, :no_fixture, :wrong_phase, :dead]

  # A rule known to witness, per phase. If one of these stops witnessing the
  # probe has broken, not the rule — a shape change in the extractor would
  # otherwise show up as "the whole tree regressed", which reads as the gate
  # working when it is the gate that is wrong.
  @sentinels %{
    syntax: "FixScientificNotation",
    semantic: "UndefinedFunction",
    pattern: "AvoidGraphemesEnumCount"
  }

  setup_all do
    results =
      Map.new(@phases, fn phase ->
        {phase, Enum.map(Witness.rules(phase), &{&1, Witness.witness(&1)})}
      end)

    {:ok, results: results}
  end

  defp short(rule), do: rule |> Module.split() |> List.last()

  defp unwitnessed(results) do
    for {_phase, rows} <- results,
        {rule, {:unwitnessed, _}} <- rows,
        do: short(rule)
  end

  defp witnessed(results) do
    for {_phase, rows} <- results,
        {rule, {:witnessed, _}} <- rows,
        do: short(rule)
  end

  # ── Vacuity ────────────────────────────────────────────────────────────────

  describe "the gate cannot pass vacuously" do
    test "the probe sees every rule in every phase", %{results: results} do
      bad =
        Enum.reject(@phases, fn phase ->
          length(results[phase]) == length(Witness.rules(phase))
        end)

      assert bad == [],
             "the probe covered fewer rules than exist in #{inspect(bad)}. Every check below " <>
               "is over the probed set, so a probe that silently sees fewer rules than the " <>
               "phase has passes while saying nothing."
    end

    test "the fixture index is non-empty for every phase" do
      empty = Enum.filter(@phases, fn phase -> Witness.index(phase) == %{} end)

      assert empty == [],
             "no fixtures were indexed for #{inspect(empty)}. Every rule would then be " <>
               "unwitnessed for want of anything to probe, and this gate would be accusing " <>
               "the whole tree of a defect in itself. Check the glob and Sourceror parsing."
    end

    test "the known-good sentinel of each phase still witnesses", %{results: results} do
      broken =
        Enum.reject(@phases, fn phase -> @sentinels[phase] in witnessed(results) end)

      assert broken == [],
             "the sentinel rule for #{inspect(broken)} stopped witnessing. These are rules " <>
               "with real, verified fixtures; if one stops firing the PROBE has broken, not " <>
               "the rule. Fix Credence.PipelineWitness before trusting any result below."
    end

    test "the overwhelming majority of rules witness — a mass regression is a probe bug",
         %{results: results} do
      total = Enum.sum(Enum.map(@phases, &length(results[&1])))
      seen = length(witnessed(results))

      assert seen * 10 >= total * 9,
             "only #{seen} of #{total} rules witnessed. The ledger is #{map_size(@ledger)} " <>
               "entries; a number this far below that means the probe stopped working, not " <>
               "that the tree rotted. Do not enlarge the ledger to make this pass."
    end
  end

  # ── The ledger polices itself ──────────────────────────────────────────────

  describe "the ledger" do
    test "names only live rules" do
      live = @phases |> Enum.flat_map(&Witness.rules/1) |> MapSet.new(&short/1)
      stale = @ledger |> Map.keys() |> Enum.reject(&MapSet.member?(live, &1)) |> Enum.sort()

      assert stale == [],
             "the ledger names rules that no longer exist: #{inspect(stale)}. Delete them."
    end

    test "every entry carries a known reason" do
      unknown =
        @ledger |> Enum.reject(fn {_rule, reason} -> reason in @reasons end) |> Enum.sort()

      assert unknown == [],
             "ledger entries with an unrecognised reason: #{inspect(unknown)}. The reason is " <>
               "not decoration — it is what says which repair applies. Known: #{inspect(@reasons)}."
    end
  end

  # ── The gate ───────────────────────────────────────────────────────────────

  describe "the gate" do
    test "every rule not on the ledger witnesses its own failure mode", %{results: results} do
      new = Enum.sort(unwitnessed(results) -- Map.keys(@ledger))

      assert new == [],
             """

             #{length(new)} rule(s) cannot be made to fire by any fixture in their own tests:

             #{Enum.map_join(new, "\n", &"  - #{&1}")}

             The rule's tests pass, and the rule is nonetheless dead in the pipeline. One of:

               * the diagnostic it matches is not one the compiler emits (check by compiling a
                 fixture with Credence.RuleHelpers.compile_and_capture/1 and reading what comes
                 back, rather than by writing the message you expect);
               * a live rule already owns that diagnostic — Semantic dispatch is first-match-wins;
               * it is a Syntax rule whose fixture PARSES, so the Syntax phase never runs;
               * the fixture exists but exercises a shape the phase cannot see.

             Adding it to @ledger is NOT one of the options. That ledger is frozen debt from
             2026-07-28 and only shrinks.
             """
    end

    test "every rule repaired since adoption has LEFT the ledger", %{results: results} do
      graduated = Enum.sort(Map.keys(@ledger) -- unwitnessed(results))

      assert graduated == [],
             """

             #{length(graduated)} ledgered rule(s) now witness through the real pipeline:

             #{Enum.map_join(graduated, "\n", &"  - #{&1} (was: #{inspect(@ledger[&1])})")}

             Remove them from @ledger in this file. That is what makes the ledger shrink and
             what makes the paydown permanent — off the ledger, the rule can never go back to
             unwitnessed without a deliberate re-freeze.
             """
    end
  end

  # ── The identities the probe's speed rests on ──────────────────────────────
  #
  # `PipelineWitness` probes each phase through its own `analyze/2` rather than
  # `Credence.analyze/2`, and probes Pattern/Syntax with a single-rule list.
  # Both are exact identities rather than approximations — but only while
  # `Credence.analyze/2` keeps its current shape and only while Pattern and
  # Syntax keep concatenating instead of dispatching. Pin both.

  describe "the probe's shortcuts are identities, not approximations" do
    @parsing_source """
    defmodule WitnessIdentityProbe do
      def run(list), do: Enum.count(list)
    end
    """

    # Fails to tokenize (`1e-10` needs a decimal point) AND is claimed by a live
    # Syntax rule. Both halves matter: the identity below holds when the Syntax
    # phase produces something, and NOT otherwise — on source that fails to
    # parse but that no Syntax rule claims, `Credence.analyze/2` falls through to
    # the Semantic ++ Pattern branch and Pattern reports its own `:parse_error`.
    # That fall-through is invisible to the probe, which only ever asks about
    # candidates its own rule fires on, but it is the reason this test is phrased
    # as "when Syntax fires" rather than "for source that does not parse".
    @non_parsing_source "x = 1e-10"

    test "for source that parses, Credence.analyze/2 is Semantic ++ Pattern" do
      opts = [assumptions: Witness.all_assumptions_on()]

      assert Credence.analyze(@parsing_source, opts).issues ==
               Credence.Semantic.analyze(@parsing_source, opts) ++
                 Credence.Pattern.analyze(@parsing_source, opts),
             "the probe reads a Semantic/Pattern rule's contribution off its own phase. If " <>
               "Credence.analyze/2 starts filtering phases against each other, that stops " <>
               "being the same answer and PipelineWitness must go back through the top level."
    end

    test "when the Syntax phase fires, Credence.analyze/2 is Syntax alone" do
      opts = [assumptions: Witness.all_assumptions_on()]
      syntax = Credence.Syntax.analyze(@non_parsing_source, opts)

      assert syntax != [],
             "the fixture no longer trips any Syntax rule, so this test proves nothing about " <>
               "the identity it exists to pin. Pick source that does not parse AND is claimed."

      assert Credence.analyze(@non_parsing_source, opts).issues == syntax
    end

    test "Pattern has no dispatch contention, so a single-rule probe is exact" do
      rule = Credence.Pattern.AvoidGraphemesEnumCount
      code = "Enum.count(String.graphemes(str))"
      opts = [assumptions: Witness.all_assumptions_on()]

      full =
        Enum.filter(
          Credence.Pattern.analyze(code, opts),
          &(&1.rule == :avoid_graphemes_enum_count)
        )

      assert Credence.Pattern.analyze(code, [rules: [rule]] ++ opts) == full,
             "narrowing `rules:` changed this rule's findings, so Pattern rules are no longer " <>
               "independent and PipelineWitness's single-rule probe is unsound."
    end

    test "Semantic IS dispatch-contended, so it is never probed narrowed" do
      # The guarantee that matters here is a negative one, so it is demonstrated
      # rather than observed: narrowing the Semantic rule set would hand every
      # rule an uncontested slot and silently delete the G3 shadowed class — 33
      # of the 86 rejects this gate exists to catch. Two probe rules that claim
      # the same diagnostic show it directly, and do not depend on two LIVE rules
      # happening to overlap today (they do not, which is C8 working).
      source = """
      defmodule WitnessContentionProbe do
        def run do
          unused = 1
          :ok
        end
      end
      """

      both = [ShadowingWinner, ShadowingLoser]

      assert [%Credence.Issue{rule: :shadowing_winner}] =
               Credence.Semantic.analyze(source, semantic_rules: both)

      # The loser is not merely ranked lower — it produces nothing at all, and
      # nothing in its own tests would ever reveal that.
      assert [%Credence.Issue{rule: :shadowing_loser}] =
               Credence.Semantic.analyze(source, semantic_rules: [ShadowingLoser])
    end
  end
end
