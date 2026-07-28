defmodule Credence.Semantic do
  @moduledoc """
  Semantic phase — fixes compiler warnings and errors.

  Uses `Code.with_diagnostics/1` to compile the source and capture
  diagnostics without permanently loading modules. Delegates to rules
  implementing `Credence.Semantic.Rule` behaviour.

  When compilation succeeds, the captured diagnostics are matched against rules
  and fixed. When compilation fails, error-level diagnostics are matched first;
  if any fix is applied, the phase retries (up to `max_passes`) to catch
  warnings that only appear once the error is resolved.

  ## Compiling source can still carry error-severity diagnostics

  "Compiles" and "has no errors" are different questions, and this phase used to
  conflate them. `Code.compile_string/2` runs `Module.ParallelChecker`, which
  pushes its findings into the same diagnostics channel `Code.with_diagnostics/1`
  reads — so `RuleHelpers.compile_and_capture/1` returns `{:ok, diagnostics}`
  (a module list came back) with `severity: :error` entries inside it.

  Elixir raises a checker diagnostic to `:error` in exactly two places, both
  struct checks in **pattern** position (`Module.Types.Of`, via
  `Module.Types.Pattern`):

      unknown key :message for struct Jason.DecodeError
      struct Foo is undefined (module Foo is not available or is yet to be defined)

  The same two checks in *expression* position stay `:warning`, which is why the
  colon-vs-dot spelling matters: `unknown key :k for struct M` (pattern, error)
  and `unknown key .k in expression:` (expr, warning) are different diagnostics.

  Filtering this branch to `severity == :warning` therefore discarded the entire
  pattern-position struct class before any rule saw it — a rule keyed on it was
  green in its own tests (which call `match?/1` and `fix/2` directly) and inert
  in production. `@compiling_severities` is the repair; `health_from/2` carries
  the matching half, so the widened pass is gated rather than merely wider.

  ## Per-pass compile-revert (C4)

  A pass applies one rule per matched diagnostic (see `find_matching_rule/2` —
  `Enum.find`, so the first rule in priority order wins and no diagnostic is
  ever handled twice). Those fixes used to be accepted unconditionally: a rule
  whose `fix/2` broke the source carried the damage into the next pass and out
  to the caller, and the trace said `{Rule, 1}` — indistinguishable from a
  clean repair.

  After each pass that changed the source, the phase now re-measures the
  source's *health* and, if the pass made it worse, attributes the damage to
  the individual fix that did it, reverts only that fix, and records it as
  `{rule, :reverted}` — the same marker the Pattern round already uses, which
  the evolution harness routes to its deterministic bugfix lane.

  ### What "worse" means, and what it deliberately does not

  This phase exists to run on source that does **not** compile, so "must
  compile" cannot be the gate. Three signals are used, in order:

    1. `:parse_regression` — the source parsed before the pass and does not
       after. A semantic rule rewrites *text*; turning parseable source into
       unparseable text is never a repair, and it is the phase's most common
       habitat (post-Syntax source parses but does not compile).

    2. `:compile_regression` — the source compiled before the pass and does
       not after. This is the exact gate `Credence.Pattern` applies per rule;
       it covers the warning pass, which is terminal and returns straight to
       the caller.

    3. `:errors_added_none_repaired` — the pass's error multiset is a *strict
       superset* of the pre-pass one: every error that was there is still
       there, verbatim, and at least one new one appeared. Nothing was
       repaired and something broke.

  **Error count is deliberately NOT the measure.** A correct repair routinely
  *raises* it, because an error that aborts expansion masks every error after
  it. Measured against this tree's own `Credence.Semantic.FixAfterOrRescueInCase`:

      # before — 2 error diagnostics
      [error] {3, 5} unexpected option :rescue in "case"
      [error] 0     cannot compile module ProbeU (errors have been logged)

      # after the CORRECT fix — 3 error diagnostics
      [error] {11, 14} undefined function missing_one/0 ...
      [error] {12, 14} undefined function missing_two/0 ...
      [error] 0        cannot compile module ProbeU (errors have been logged)

  A count gate reverts that repair. The strict-superset form does not, and it
  cannot be fooled by unmasking in general: unmasking requires the masking
  error to have been resolved, and a resolved error leaves the multiset, so a
  superset proves nothing was unmasked. The cost is that a pass which repairs
  one error while introducing another is *not* flagged — the ambiguous case is
  left alone on purpose, because reverting a genuine repair is the more
  expensive mistake.

  ### Attribution

  Every fix in a pass is recorded with the exact source it saw and the exact
  source it produced, so attribution replays no rule code: the health of each
  intermediate state is compared with the state immediately before it, and any
  step that degraded it is a culprit. The surviving fixes are then replayed on
  the pre-pass source — sound because the pass applies diagnostics
  right-to-left, so dropping a fix never invalidates the positions of the fixes
  that come after it — and the result is accepted only if it is not worse than
  the pre-pass source. If it still is, or if no single step accounts for the
  damage, the whole pass is reverted and every fix that changed the source is
  marked `:reverted`.

  Cost: one extra `Code.compile_string` per pass that changed the source, plus
  one per changed step only on the (abnormal) regression path.
  """

  require Logger
  alias Credence.RuleHelpers

  @default_max_passes 3

  # What a *successful* compile can report. Not just `:warning` — see the
  # moduledoc: the type checker emits `:error` for struct problems in pattern
  # position while the module still compiles.
  @compiling_severities [:warning, :error]

  @typedoc """
  A trace entry: the rule, and how many diagnostics it fixed — or `:reverted`
  (its fix made the source worse and was undone) or `:no_op` (it matched a
  diagnostic and returned the source unchanged). See `t:Credence.rule_outcome/0`,
  which is the closed set this is drawn from.
  """
  @type trace_entry :: {module(), non_neg_integer() | :reverted | :no_op}

  @spec analyze(String.t(), keyword()) :: [Credence.Issue.t()]
  def analyze(source, opts \\ []) do
    rules = rules(opts)

    case RuleHelpers.compile_and_capture(source) do
      {:ok, diagnostics} ->
        diagnostics
        |> Enum.filter(&(&1.severity in @compiling_severities))
        |> Enum.flat_map(&match_rules(&1, source, rules))

      {:error, diagnostics} ->
        diagnostics
        |> Enum.filter(&(&1.severity == :error))
        |> Enum.flat_map(&match_rules(&1, source, rules))
    end
  end

  @spec fix(String.t(), keyword()) :: String.t()
  def fix(source, opts \\ []) do
    {code, _applied} = fix_with_trace(source, opts)
    code
  end

  @doc """
  Like `fix/2`, but also returns a list of `{rule_module, issue_count}` tuples
  for every rule that actually fired and was applied. A rule whose fix made the
  source worse comes back as `{rule_module, :reverted}` instead — see the
  moduledoc's per-pass compile-revert section.

  Every step is logged via `Logger.debug` with `[credence_fix]` prefix:
  pass number, severity being targeted, rule name, whether the source
  changed, and a before/after diff of the lines that were modified. A revert is
  logged at `Logger.warning`, with the reverted diff, since it is never routine.
  """
  @spec fix_with_trace(String.t(), keyword()) :: {String.t(), [trace_entry()]}
  def fix_with_trace(source, opts \\ []) do
    max_passes = Keyword.get(opts, :max_passes, @default_max_passes)

    Logger.debug(
      "[credence_fix] starting semantic fix pipeline (max #{max_passes} passes, #{length(rules(opts))} rules)"
    )

    {code, applied} = do_fix_traced(source, opts, max_passes, 1, [])

    summary =
      Enum.map_join(applied, ", ", fn {mod, count_or_status} ->
        "#{RuleHelpers.rule_name(mod)}(#{count_or_status})"
      end)

    Logger.debug("[credence_fix] semantic done. Applied: [#{summary}]")

    {code, applied}
  end

  defp do_fix_traced(source, _opts, max_passes, pass, applied) when pass > max_passes do
    Logger.debug("[credence_fix] semantic pass limit reached (#{max_passes}), stopping")
    {source, Enum.reverse(applied)}
  end

  defp do_fix_traced(source, opts, max_passes, pass, applied) do
    compiled = RuleHelpers.compile_and_capture(source)

    case compiled do
      {:ok, diagnostics} ->
        # Compilation succeeded — fix what the checker reported (terminal pass,
        # no retry needed). Both severities: see the moduledoc's
        # "Compiling source can still carry error-severity diagnostics".
        reported = Enum.filter(diagnostics, &(&1.severity in @compiling_severities))

        Logger.debug(
          "[credence_fix] semantic pass #{pass}: compilation OK, #{length(reported)} diagnostic(s)"
        )

        {fixed, new_applied} = run_pass(source, compiled, reported, opts, pass)
        {fixed, Enum.reverse(new_applied ++ applied)}

      {:error, diagnostics} ->
        # Compilation failed — fix errors, then retry
        errors = Enum.filter(diagnostics, &(&1.severity == :error))

        if errors == [] do
          Logger.debug(
            "[credence_fix] semantic pass #{pass}: compilation raised an exception " <>
              "(0 diagnostics captured — see Code.compile_string raised log above)"
          )
        else
          Logger.debug(
            "[credence_fix] semantic pass #{pass}: compilation FAILED, #{length(errors)} error(s)"
          )
        end

        {fixed, new_applied} = run_pass(source, compiled, errors, opts, pass)

        if fixed != source do
          Logger.debug("[credence_fix] semantic pass #{pass}: source changed, retrying...")
          do_fix_traced(fixed, opts, max_passes, pass + 1, new_applied ++ applied)
        else
          Logger.debug(
            "[credence_fix] semantic pass #{pass}: no rule could fix the error(s), stopping"
          )

          {fixed, Enum.reverse(new_applied ++ applied)}
        end
    end
  end

  # One pass: apply every matching rule's fix, then gate the result. Returns
  # trace entries in reverse application order, the accumulation order
  # `do_fix_traced/5` expects.
  defp run_pass(source, compiled, diagnostics, opts, pass) do
    {fixed, steps} = apply_fixes_traced(source, diagnostics, opts)

    if fixed == source do
      # Nothing changed, so nothing can have got worse — and the gate's compile
      # would be pure cost. (Rules that matched and returned identical source
      # still appear in the trace — as `{rule, :no_op}` since T3.2.)
      {source, trace(steps, [])}
    else
      guard_pass(source, compiled, fixed, steps, pass)
    end
  end

  # C4. The pass changed the source: re-measure and, if it went backwards, find
  # out which fix did it. `compiled` is the pre-pass compile result
  # `do_fix_traced/5` already has in hand, so the baseline costs nothing.
  defp guard_pass(source, compiled, fixed, steps, pass) do
    baseline = health_from(source, compiled)
    post = health(fixed)

    case verdict(baseline, post) do
      :ok ->
        {fixed, trace(steps, [])}

      {:worse, reason} ->
        Logger.warning(
          "[credence_fix] semantic pass #{pass}: the pass made the source WORSE " <>
            "(#{reason_text(reason)}) — attributing it to the fix that did it"
        )

        settle(source, steps, attribute(steps, baseline, fixed, post), baseline, pass, reason)
    end
  end

  # No single step degraded the source relative to the state right before it,
  # yet the pass as a whole did: the damage is emergent across fixes and there
  # is no culprit to name. Revert everything rather than guess.
  defp settle(source, steps, [], _baseline, pass, reason) do
    Logger.warning(
      "[credence_fix] semantic pass #{pass}: no single fix accounts for " <>
        "#{reason_text(reason)} — reverting the whole pass"
    )

    {source, trace(steps, effective(steps))}
  end

  defp settle(source, steps, culprits, baseline, pass, reason) do
    Enum.each(culprits, fn step ->
      name = RuleHelpers.rule_name(step.rule)

      Logger.warning(
        "[credence_fix] #{name}: fix made the source worse (#{reason_text(reason)}), reverting"
      )

      # Visibility (Tunex `08` T1.3): the broken before/after belongs in the row
      # log so the harness's deterministic bugfix lane has a seed to work from.
      RuleHelpers.log_diff(name, step.before, step.after)
    end)

    culprit_ids = MapSet.new(culprits, & &1.index)
    retained = Enum.reject(steps, &MapSet.member?(culprit_ids, &1.index))

    case replay(source, retained) do
      {:error, reason} ->
        Logger.warning(
          "[credence_fix] semantic pass #{pass}: replaying the surviving fix(es) raised " <>
            "#{inspect(reason)} — reverting the whole pass"
        )

        {source, trace(steps, effective(steps))}

      {:ok, ^source} ->
        {source, trace(steps, culprits)}

      {:ok, candidate} ->
        if verdict(baseline, health(candidate)) == :ok do
          # The innocent fixes stand on their own. This is the Pattern round's
          # discipline: one misbehaving rule costs its own fix, not the pass.
          {candidate, trace(steps, culprits)}
        else
          Logger.warning(
            "[credence_fix] semantic pass #{pass}: still worse after reverting the " <>
              "culprit(s) — reverting the whole pass"
          )

          {source, trace(steps, effective(steps))}
        end
    end
  end

  # The steps that individually degraded the source, in application order.
  # No rule code is re-run: each step recorded the source it produced, and
  # health is a function of that string alone. The last changed step's output
  # *is* the pass output, so its health is the `post` we already computed.
  defp attribute(steps, baseline, fixed, post) do
    {culprits, _health} =
      Enum.reduce(steps, {[], baseline}, fn step, {acc, previous} ->
        if step.after == step.before do
          {acc, previous}
        else
          current = if step.after == fixed, do: post, else: health(step.after)
          acc = if verdict(previous, current) == :ok, do: acc, else: [step | acc]
          {acc, current}
        end
      end)

    Enum.reverse(culprits)
  end

  # Re-apply the surviving fixes to the pre-pass source. Sound because
  # `apply_fixes_traced/3` orders diagnostics right-to-left: a dropped fix only
  # ever edited text to the RIGHT of every fix that follows it, so the ones that
  # follow see the same bytes they saw the first time.
  #
  # It is nonetheless an input each rule was NOT called with during the pass —
  # the culprit's edit is missing from it — so a rule can raise here where it did
  # not before. The Semantic round has no per-rule crash isolation yet (C6), and
  # a gate whose job is to prevent damage must not itself become a new way to
  # take the call down: a raising replay degrades to the conservative answer,
  # reverting the whole pass.
  defp replay(source, steps) do
    {:ok, Enum.reduce(steps, source, fn step, src -> step.rule.fix(src, step.diagnostic) end)}
  rescue
    e -> {:error, e}
  catch
    kind, value -> {:error, {kind, value}}
  end

  defp effective(steps), do: Enum.filter(steps, &(&1.after != &1.before))

  # T3.2. Three outcomes, not two. A step whose fix returned the source it was
  # given fixed nothing, and reporting it as `{rule, 1}` was a positive claim
  # that it had — worse than the Pattern round's matching bug, which merely
  # dropped such a rule from the trace. `:no_op` is the honest answer, and it is
  # the signal the harness's bugfix lane needs: a rule that matches a diagnostic
  # and then declines to act on it is a rule holding a dispatch slot for nothing
  # (first-match-wins means no other rule gets to try).
  defp trace(steps, reverted) do
    reverted_ids = MapSet.new(reverted, & &1.index)

    steps
    |> Enum.map(fn step ->
      cond do
        MapSet.member?(reverted_ids, step.index) -> {step.rule, :reverted}
        step.after == step.before -> {step.rule, :no_op}
        true -> {step.rule, 1}
      end
    end)
    |> Enum.reverse()
  end

  # How healthy a source is, as a value the gate can order. `parses?` is only
  # consulted when the source does not compile — a compiling source parses by
  # construction, and `Code.string_to_quoted/1` is not free.
  defp health(source), do: health_from(source, RuleHelpers.compile_and_capture(source))

  # Compiling source is NOT error-free source: the type checker reports
  # `unknown key :k for struct M` at `:error` while the module still compiles.
  # This clause used to hardcode `errors: %{}`, which made `verdict/2`
  # structurally incapable of returning anything but `:ok` on this branch — the
  # whole warning pass ran with no revert gate behind it. Counting them here is
  # what gives the widened pass (see `@compiling_severities`) a working C4.
  # `compiles?` stays `true`: flipping it would read every type error as a
  # `:compile_regression` and revert correct repairs.
  defp health_from(_source, {:ok, diagnostics}),
    do: %{parses?: true, compiles?: true, errors: error_frequencies(diagnostics)}

  defp health_from(source, {:error, diagnostics}) do
    %{parses?: parses?(source), compiles?: false, errors: error_frequencies(diagnostics)}
  end

  defp error_frequencies(diagnostics) do
    diagnostics
    |> Enum.filter(&(&1.severity == :error))
    |> Enum.map(& &1.message)
    |> Enum.frequencies()
  end

  # See the moduledoc for why error COUNT is not one of these.
  defp verdict(before, after_) do
    cond do
      before.parses? and not after_.parses? -> {:worse, :parse_regression}
      before.compiles? and not after_.compiles? -> {:worse, :compile_regression}
      strict_superset?(after_.errors, before.errors) -> {:worse, :errors_added_none_repaired}
      true -> :ok
    end
  end

  # Multiset containment plus at least one addition. Multiset (not set) matters:
  # two identical messages at different positions are two errors, and repairing
  # one of them must read as progress, not as "the error is still there".
  defp strict_superset?(errors_after, errors_before) do
    Enum.all?(errors_before, fn {message, n} -> Map.get(errors_after, message, 0) >= n end) and
      total(errors_after) > total(errors_before)
  end

  defp total(frequencies), do: frequencies |> Map.values() |> Enum.sum()

  # `Code.string_to_quoted/1` emits tokenizer warnings (e.g. deprecated
  # single-quoted charlists) that this check does not care about and must not
  # print — it runs on every gated pass.
  defp parses?(source) do
    {result, _diagnostics} = Code.with_diagnostics(fn -> Code.string_to_quoted(source) end)
    match?({:ok, _}, result)
  end

  defp reason_text(:parse_regression), do: "the source no longer parses"
  defp reason_text(:compile_regression), do: "the source no longer compiles"

  defp reason_text(:errors_added_none_repaired),
    do: "it added compile error(s) and repaired none"

  defp apply_fixes_traced(source, diagnostics, opts) do
    rules = rules(opts)

    # Apply rightmost (highest-column) diagnostics first so column-aware
    # rules don't see stale columns after an earlier fix mutates the
    # line. Insertions / underscoring before a binding shift everything
    # to the right of it; processing right-to-left keeps untouched
    # columns valid for the rest of the pass.
    {fixed, steps} =
      diagnostics
      |> Enum.sort_by(&position_sort_key/1, :desc)
      |> Enum.reduce({source, []}, fn diagnostic, {src, steps} ->
        case find_matching_rule(diagnostic, rules) do
          nil ->
            # Log the FULL diagnostic (message + position + severity), not just
            # the message — this is the new-semantic-rule signal (Tunex `07`
            # §3.3/§3.6, `08` T1.3b): the implementer needs the position +
            # severity to build a *real* test `diag` + `match?`, so a fabricated
            # diagnostic can't ship a rule that's dead in production.
            Logger.debug("[credence_fix] no rule matched diagnostic: #{inspect(diagnostic)}")

            {src, steps}

          rule ->
            name = RuleHelpers.rule_name(rule)

            Logger.debug("[credence_fix] #{name}: matched diagnostic, running fix...")

            fixed = rule.fix(src, diagnostic)

            if fixed == src do
              Logger.debug("[credence_fix] #{name}: fix returned IDENTICAL source (no change)")
            else
              RuleHelpers.log_diff(name, src, fixed)
            end

            step = %{
              index: length(steps),
              rule: rule,
              diagnostic: diagnostic,
              before: src,
              after: fixed
            }

            {fixed, [step | steps]}
        end
      end)

    {fixed, Enum.reverse(steps)}
  end

  # Sort key for ordering diagnostics within a pass: `{line, col}` if
  # both are present, `{line, 0}` if only the line is known, `{0, 0}`
  # otherwise. Used with `:desc` so rightmost-on-line is applied first.
  defp position_sort_key(%{position: {line, col}})
       when is_integer(line) and is_integer(col),
       do: {line, col}

  defp position_sort_key(%{position: {line, _}}) when is_integer(line), do: {line, 0}
  defp position_sort_key(%{position: line}) when is_integer(line), do: {line, 0}
  defp position_sort_key(_), do: {0, 0}

  defp match_rules(diagnostic, source, rules) do
    case find_matching_rule(diagnostic, rules) do
      nil ->
        []

      rule ->
        if should_report?(rule, diagnostic, source) do
          [rule.to_issue(diagnostic)]
        else
          []
        end
    end
  end

  defp should_report?(rule, diagnostic, source) do
    if function_exported?(rule, :should_report?, 2) do
      rule.should_report?(diagnostic, source)
    else
      true
    end
  end

  # First match wins: a diagnostic is handled by exactly one rule, the
  # earliest in priority order. That is what makes a pass's fixes a flat,
  # per-diagnostic sequence, and therefore what makes them attributable.
  defp find_matching_rule(diagnostic, rules) do
    Enum.find(rules, fn rule -> rule.match?(diagnostic) end)
  end

  # `:semantic_rules` is a testing/advanced seam, NOT the Pattern round's
  # `:rules`. It is deliberately a different key: `Credence.analyze/2` and
  # `Credence.fix/2` hand the same `opts` to every round, and a Pattern rule
  # list reaching this round would blow up in `rule.match?/1`.
  defp rules(opts), do: Keyword.get(opts, :semantic_rules, default_rules())

  @doc false
  def default_rules do
    RuleHelpers.discover_rules(Credence.Semantic.Rule)
  end
end
