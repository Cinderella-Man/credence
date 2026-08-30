defmodule Credence.RuleSelfRepairTest do
  @moduledoc """
  Gate: every Pattern rule's own documented anti-pattern is actually repaired by
  the pipeline — not by calling the rule directly, but by running the round the
  way a user does.

  ## Why this is a different question from "the rule has a fix"

  `rule_card_test.exs` proves each `## Bad` example makes its own rule fire, and
  the per-rule fix tests prove `fix_patches/2` produces the right output. Neither
  proves the two meet. A rule can pass both and still repair nothing in practice:
  its patches can be discarded by the safety invariants, or its output can be
  reverted for adding a compile error, and the only trace is a `Logger.warning`
  nobody reads.

  Measured when this gate was written: **six of 156 rules could not repair their
  own documented example end-to-end** — three `:reverted`, three
  `:patch_rejected`. All six turned out to be defects in the *examples* rather
  than the rules; every one was a bare snippet rather than a module, and

    * `Agent.get_and_modify(__MODULE__, ...)` at the top level **executes** during
      the compile check and exits with `:noproc`, so before and after differed by
      an incidental error message;
    * `defp helper(x)` outside a module traded "cannot invoke `@doc`/1 outside
      module" for "cannot invoke `defp`/2 outside module" — a different error, so
      correctly rejected;
    * `[h | t] ->` with only `# ... complex body` under it is not valid Elixir.

  Wrapped in modules, all six repair cleanly. That is the point of the gate: the
  examples are also the D8a duplicate corpus and the `rule_card` fixtures, so an
  unrealistic one degrades three things at once, and nothing else was checking.
  """
  # This gate COMPILES every rule's documented example, which used to make it
  # unsafe to run concurrently: the examples inherited their fixtures' module
  # names, 21 said `defmodule Bad` and 14 said `defmodule M`, and the Erlang
  # code server is global — so two async tests compiling `Bad` raced, one
  # deleting the module the other was mid-check on. It surfaced three times, as
  # `NoDuplicateFunctionClauses -> reverted` and twice in the Semantic card
  # gate, each passing when run alone.
  #
  # Every example module name is now unique (derived from its rule), so the
  # hazard is gone at the source rather than worked around here, and this can be
  # `async: true` again. A `rule_card_test.exs` gate asserts the uniqueness, so
  # it cannot quietly come back.
  use ExUnit.Case, async: true

  # The Semantic half compiles every candidate fixture of all 89 rules. Alone it
  # takes ~7s; under a loaded full suite it crossed the 60s default and failed as
  # a TIMEOUT, which reads exactly like a real regression. Same trap the T2.5
  # idempotency sweep fell into — a `timeout:` under concurrent load, re-run
  # quiet and green. The gate is not slow because anything is wrong; it is slow
  # because it compiles.
  @moduletag timeout: :timer.minutes(10)

  alias Credence.RuleDuplication

  defp successfully_applied?(applied, rule) do
    match?({^rule, count} when is_integer(count), List.keyfind(applied, rule, 0))
  end

  defp repaired_output?(before, after_source, applied, rule, anti_pattern_survives?) do
    before != after_source and successfully_applied?(applied, rule) and
      not anti_pattern_survives?
  end

  defp cascade_applied?(applied, rule), do: successfully_applied?(applied, rule)

  defp pattern_survives?(rule, source) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      rule.check(ast, source: source) != []
    else
      _ -> true
    end
  rescue
    _ -> true
  catch
    _, _ -> true
  end

  # Rules whose Bad example is repaired by a DIFFERENT rule reaching it first.
  # This is the Pattern round working as designed — it is a cascade, and the
  # earlier rule leaves nothing for the later one to match. Ledgered rather than
  # waved through so that a rule going dark for any other reason still fails.
  @cascade %{
    # Both reach `String.length/1`; pinned in graphemes_count_family_test.exs
    # and ledgered as an overlapping-not-duplicate pair in D8a.
    Credence.Pattern.NoEnumCountForLength => Credence.Pattern.AvoidGraphemesEnumCount,
    Credence.Pattern.PreferGraphemesForCharacterUniqueness =>
      Credence.Pattern.NoEnumCountForLength,
    Credence.Pattern.PreferMultiClauseReduceFn => Credence.Pattern.PreferCondForNestedIf
  }

  describe "the documented anti-pattern does not survive the pipeline" do
    test "every Pattern rule's `## Bad` example is repaired end-to-end" do
      rules = Credence.MetaTestSupport.rules()

      outcomes =
        for rule <- rules,
            bad = RuleDuplication.bad_example(rule),
            bad not in [nil, ""] do
          {code, applied} = Credence.Pattern.fix_with_trace(bad)
          survives? = pattern_survives?(rule, code)

          status =
            case List.keyfind(applied, rule, 0) do
              {^rule, count} when is_integer(count) ->
                if repaired_output?(bad, code, applied, rule, survives?),
                  do: :repaired,
                  else: :survived

              {^rule, other} ->
                other

              nil ->
                cond do
                  code == bad -> :untouched
                  survives? -> :survived
                  true -> :repaired_by_another
                end
            end

          {rule, status}
        end

      assert length(outcomes) >= 156,
             "only #{length(outcomes)} rules had an example to run; the extractor has regressed"

      failures =
        for {rule, status} <- outcomes,
            status != :repaired,
            not (status == :repaired_by_another and Map.has_key?(@cascade, rule)),
            do: {rule, status}

      assert failures == [],
             """
             These rules report their own documented anti-pattern but the pipeline
             leaves it unrepaired:

             #{Enum.map_join(failures, "\n", fn {r, s} -> "  #{inspect(r)} -> #{s}" end)}

             `:patch_rejected` means the safety invariants discarded the patches
             (output did not parse, or the comment multiset changed).
             `:reverted` means the output added a compile error the input did not
             have. `:untouched` means the fix ran and changed nothing.

             Check the EXAMPLE first — every instance found so far was a bare
             snippet that no real file would contain, and wrapping it in a module
             fixed it. Only then suspect the rule.
             """
    end

    test "each ledgered cascade is still a cascade, and still by the same rule" do
      stale =
        for {rule, expected} <- @cascade do
          bad = RuleDuplication.bad_example(rule)
          {code, applied} = Credence.Pattern.fix_with_trace(bad)

          cond do
            List.keyfind(applied, rule, 0) != nil -> {rule, :fires_itself_now}
            not cascade_applied?(applied, expected) -> {rule, :different_rule_now}
            pattern_survives?(rule, code) -> {rule, :anti_pattern_survived}
            true -> nil
          end
        end
        |> Enum.reject(&is_nil/1)

      assert stale == [],
             """
             The cascade ledger is out of date — it may only shrink:

             #{Enum.map_join(stale, "\n", fn {r, why} -> "  #{inspect(r)}: #{why}" end)}

             `:fires_itself_now` means the entry is paid down; delete it.
             `:different_rule_now` means the cascade order changed, which is a
             behaviour change worth understanding before re-pointing the entry.
             """
    end
  end

  describe "control" do
    # The gate reads a status out of the applied-rules trace. A trace that
    # reported success for everything would make it vacuous, so: a rule given an
    # input it has nothing to say about must come back `:untouched`.
    test "a rule with nothing to do is not reported as repaired" do
      clean = "defmodule RsrClean do\n  def f(x), do: x\nend\n"

      {code, applied} = Credence.Pattern.fix_with_trace(clean)

      assert code == clean
      assert applied == []
    end

    test "a positive trace is not success when the anti-pattern survives" do
      rule = Credence.Pattern.NoEnumCountForLength

      refute repaired_output?("before", "after", [{rule, 1}], rule, true)
    end

    test "a failed cascade trace entry is not an applied repair" do
      rule = Credence.Pattern.NoEnumCountForLength

      refute cascade_applied?([{rule, :reverted}], rule)
    end
  end

  # ── The same question for the Semantic round ───────────────────────────
  #
  # A Semantic rule reaches its `fix/2` only if the compiler really emits a
  # diagnostic its `match?/1` accepts AND no earlier rule claims that diagnostic
  # first (`Enum.find` — first match wins). `PipelineWitness` proves the
  # reporting half of that end-to-end. This is the fixing half.
  #
  # Result the day it was written: **89 of 89**, no ledger. Recorded because the
  # first attempt said 16 rules were broken, and it was the probe that was wrong
  # — it tried each rule's SHORTEST fixture, and for those 16 the shortest is a
  # decline case (`should_report?/2` says no, or the fix is deliberately a
  # no-op). A rule needs one fixture it repairs, not every fixture.
  describe "the Semantic round repairs what it reports" do
    test "every Semantic rule fixes at least one of its own fixtures" do
      rules = Credence.Semantic.default_rules()

      unfixed =
        for rule <- rules,
            not Enum.any?(Credence.PipelineWitness.candidates(rule), fn candidate ->
              is_binary(candidate) and repaired_by?(rule, candidate)
            end),
            do: rule

      assert length(rules) >= 89,
             "only #{length(rules)} Semantic rules discovered; discovery has regressed"

      assert unfixed == [],
             """
             These Semantic rules never repair any fixture in their own test
             files through `Credence.Semantic.fix_with_trace/1`:

             #{Enum.map_join(unfixed, "\n  ", &inspect/1)}

             Check whether the rule is reached at all before touching its fix:
             an earlier rule claiming the same diagnostic at the dispatch slot
             looks identical from here, and `dispatch_contention_test.exs` is
             where that shows up.
             """
    end

    defp repaired_by?(rule, source) do
      {code, applied} = Credence.Semantic.fix_with_trace(source)

      repaired_output?(
        source,
        code,
        applied,
        rule,
        Credence.Semantic.analyze(code, semantic_rules: [rule]) != []
      )
    rescue
      _ -> false
    catch
      _, _ -> false
    end

    test "CONTROL: repaired_by?/2 is false for a rule the source does not trigger" do
      refute repaired_by?(
               Credence.Semantic.UnusedVariable,
               "defmodule RsrSemClean do\n  def f(x), do: x\nend\n"
             )
    end
  end
end
