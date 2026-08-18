defmodule Credence.FixOrDrop do
  @moduledoc """
  The oracle behind `test/fix_or_drop_test.exs`: does any rule report a finding
  that nothing then repairs?

  CONTEXT.md's standing policy is *fix or drop it* — "every rule either fixes its
  problem or it doesn't exist". Until this module existed nothing enforced it.
  `test/no_op_trace_test.exs` proves a no-op is *reported* in the trace; it does
  not forbid one. So a rule could report findings it declined to fix and stay
  green forever, which is exactly what 24 findings across 9 rules were doing.

  ## What counts as a violation, and what deliberately does not

  For each candidate source of a rule, `probe/2` runs the rule ALONE and classes
  the outcome:

    * `:silent` — `check/2` found nothing. Not a violation.
    * `:fixed` — `check/2` fired and the rule's own fix changed the source.
    * `{:noop, reason}` — `check/2` fired and the rule's own fix changed nothing.

  A `{:noop, _}` is **not** automatically a violation, because of cascades. The
  Pattern round re-parses between rules, so a finding one rule reports can be
  legitimately repaired by a sibling — `NoEnumTakeNegative` defers to
  `PreferDescSortOverNegativeTake` on `sort |> take(-n)` by design. `violation?/2`
  therefore asks the question that actually matters:

      the rule's own fix changed nothing
      AND the full Pattern round changed nothing either
      AND the rule still reports the finding afterwards

  Only then is the finding genuinely raised and left unrepaired. Measured over
  the tree at adoption: fixture-level fix coverage **1486/1515 = 98.1%**, 30
  no-ops, of which 6 are cascade-rescued and **24 are violations across 8 rules**
  (9 before `NoRedundantListTraversal` was paid down the same day).

  The first version of this measurement said 46 across 13 rules. It was wrong,
  and how it was wrong is worth keeping: it drew candidates from
  `PipelineWitness.candidates/1`, which over-collects by design, so 22 of the 46
  were *prose* — test names and doc sentences that happen to parse as Elixir. One
  of them, `"detects nested call: Enum.join(Enum.map(...))"`, made `UseMapJoin`
  fire and then crashed its fix, and would have been reported as a rule defect.
  A gate that accuses a rule of a bug needs a precise input set, not a generous
  one.

  ## The three reasons are different defects

    * `:no_patches` — the fix declined outright. A scope mismatch: `check/2`
      admits a shape `fix_patches/2` does not handle. The repair is to share one
      predicate between them (commit 4115c59's remedy) or to widen the fix.
    * `:patch_rejected` — the fix DID emit patches and
      `RuleHelpers.apply_rule_fix_with_status/3` discarded them because the
      output did not parse or the comment multiset changed. That is a **bug in
      the fix**, not a scope decision, and it is invisible from a test's point of
      view because it looks identical to "the rule had nothing to do".
    * `{:crashed, _}` — `fix_patches/2` raised. Crash isolation keeps the run
      alive and costs only that rule's findings, so a crash on an odd AST shape
      hides as a silent no-finding.

  Kept as a separate support module rather than inlined in the test because the
  same probe is what the paydown is measured with.
  """

  alias Credence.MetaTestSupport
  alias Credence.RuleHelpers
  alias Credence.RuleName

  @type reason :: :no_patches | :patch_rejected | :ok_identical | {:crashed, module()}
  @type outcome :: :silent | :fixed | {:noop, reason()}

  @doc """
  Run `rule` alone over `source` and class the outcome.

  A raising `check/2` is reported as `:silent` rather than swallowed into a
  violation: a crash there is a different defect, owned by
  `test/rule_crash_isolation_test.exs`, and conflating the two would make this
  gate's failures ambiguous.
  """
  @spec probe(module(), String.t()) :: outcome()
  def probe(rule, source) do
    case check(rule, source) do
      [] ->
        :silent

      :check_raised ->
        :silent

      _issues ->
        case fix(rule, source) do
          {:ok, fixed} when fixed != source -> :fixed
          {:ok, _identical} -> {:noop, :ok_identical}
          {:noop, reason} -> {:noop, reason}
        end
    end
  end

  @doc """
  Is this `{rule, source}` a genuine "reported and left unfixed"?

  Returns `false` when a sibling rule repairs it in the full Pattern round and
  the finding is gone afterwards — that is a cascade, and the finding did get
  fixed.
  """
  @spec violation?(module(), String.t()) :: boolean()
  def violation?(rule, source) do
    case probe(rule, source) do
      {:noop, _reason} -> not cascade_rescued?(rule, source)
      _ -> false
    end
  end

  @doc """
  The rule's own fixtures — every string sitting in a fixture position in its
  three test files.

  Deliberately NOT `PipelineWitness.candidates/1`, whose index over-collects on
  purpose: it files every string literal in every file that references the rule,
  because a witness only has to be found once and a false candidate costs
  nothing there. It costs a great deal here. Its `plausible_code?/1` filter is
  `String.length(s) > 4 and has a non-word character`, so a *test name* like
  `"detects nested call: Enum.join(Enum.map(...))"` is collected, parses, makes
  the rule fire, and then crashes the fix on an argument list prose never meant
  to supply. This gate would have demanded a rule repair three test names.

  `MetaTestSupport.fixtures/1` is the precise index instead — strings bound to
  `code`/`input`/`expected`/… or passed to a known RuleCase verb. It misses
  fixtures bound to a module attribute, which under-reports; that is the safe
  direction for a gate whose failure message accuses a rule of a defect.
  """
  @spec fixtures(module()) :: [String.t()]
  def fixtures(rule) do
    %{snake: snake, test_dir: dir} = RuleName.from_module(rule)

    ["#{dir}/#{snake}_check_test.exs", "#{dir}/#{snake}_fix_test.exs"]
    |> Enum.filter(&File.exists?/1)
    |> Enum.flat_map(fn path ->
      path
      |> File.read!()
      |> Sourceror.parse_string!()
      |> MetaTestSupport.fixtures()
      |> Enum.flat_map(&literal/1)
    end)
    |> Enum.uniq()
    |> Enum.filter(&match?({:ok, _}, Sourceror.parse_string(&1)))
  end

  defp literal({:__block__, _, [s]}) when is_binary(s), do: [s]
  defp literal(s) when is_binary(s), do: [s]

  # `~S'...'` — the form `Credence.FixtureHealer` rewrites any fixture containing a
  # double quote into, so dropping it silently excluded every quote-carrying
  # fixture in the suite (measured: 832 occurrences across 109 rule test files)
  # from this gate AND from `fixture_scope_parity_test.exs`. `~S` does not
  # interpolate, so its body is a single literal segment and needs no evaluation.
  defp literal({:sigil_S, _, [{:<<>>, _, [s]}, _modifiers]}) when is_binary(s), do: [s]

  defp literal(_), do: []

  @doc "Every `{rule, source, reason}` violation across `rules`."
  @spec violations([module()]) :: [{module(), String.t(), reason()}]
  def violations(rules) do
    Enum.flat_map(rules, fn rule ->
      rule
      |> fixtures()
      |> Enum.flat_map(fn source ->
        case probe(rule, source) do
          {:noop, reason} ->
            if cascade_rescued?(rule, source), do: [], else: [{rule, source, reason}]

          _ ->
            []
        end
      end)
    end)
  end

  @doc """
  Fixture-level fix coverage: `{fixed, fired}` over `rules`.

  Reported alongside the violation count because the two answer different
  questions — coverage is the rate, violations are the population, and a rule can
  sit at 95% and still be complaining about something nothing repairs.
  """
  @spec coverage([module()]) :: {non_neg_integer(), non_neg_integer()}
  def coverage(rules) do
    Enum.reduce(rules, {0, 0}, fn rule, acc ->
      rule
      |> fixtures()
      |> Enum.reduce(acc, fn source, {fixed, fired} ->
        case probe(rule, source) do
          :fixed -> {fixed + 1, fired + 1}
          {:noop, _} -> {fixed, fired + 1}
          :silent -> {fixed, fired}
        end
      end)
    end)
  end

  # ── internals ──────────────────────────────────────────────────────────────

  defp check(rule, source) do
    rule.check(Sourceror.parse_string!(source), source: source)
  rescue
    _ -> :check_raised
  end

  defp fix(rule, source) do
    case RuleHelpers.apply_rule_fix_with_status(rule, source) do
      {:ok, fixed} -> {:ok, fixed}
      {reason, _source} -> {:noop, reason}
    end
  rescue
    e -> {:noop, {:crashed, e.__struct__}}
  end

  # The finding must be GONE after the full round, not merely the source changed:
  # another rule editing an unrelated line elsewhere in the same fixture would
  # otherwise read as a rescue.
  defp cascade_rescued?(rule, source) do
    {fixed, _trace} = Credence.Pattern.fix_with_trace(source)

    fixed != source and Credence.Pattern.analyze(fixed, rules: [rule]) == []
  rescue
    _ -> false
  end
end
