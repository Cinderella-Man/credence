defmodule Credence.Pattern do
  @moduledoc """
  Pattern phase — detects and fixes anti-patterns in Elixir code.

  Delegates to the rules implementing the `Credence.Pattern.Rule` behaviour.
  Rules are discovered automatically and run in priority order (lower first),
  with module name as tiebreaker for determinism.
  """

  require Logger
  alias Credence.RuleHelpers

  @spec analyze(String.t(), keyword()) :: [Credence.Issue.t()]
  def analyze(code_string, opts \\ []) do
    opts = Keyword.put_new(opts, :source, code_string)

    case Sourceror.parse_string(code_string) do
      {:ok, ast} ->
        Enum.flat_map(rules(opts), fn rule -> reject_dsl_unfixable(rule, ast, opts) end)

      {:error, {meta, error_msg, token}} ->
        [parse_error_issue(Keyword.get(meta, :line), error_msg, token)]
    end
  end

  # The DSL gate, analyze side. A finding is suppressed exactly when its own fix
  # would be dropped by the fix-side gate — never report what we will not fix.
  # Both gates derive from the SAME thing: `RuleHelpers.dsl_dropped_ranges/3`
  # returns the patch ranges this rule's `fix_patches/2` lands inside an
  # `unsafe_in_dsl/0` block (the exact patches `apply_rule_fix/3` drops). A
  # finding inside one of those ranges has no surviving fix, so it is suppressed.
  # The two gates therefore cannot disagree: same rule, same patches, same blocks.
  # A rule with no DSL sensitivity returns `[]` and is untouched.
  # No findings means nothing to suppress, so the (fix_patches-priced)
  # dropped-ranges computation is skipped — on clean files it would otherwise
  # run for every `unsafe_in_dsl` rule.
  defp reject_dsl_unfixable(rule, ast, opts) do
    case isolate(rule, :check, [], fn -> rule.check(ast, opts) end) do
      [] ->
        []

      issues ->
        case Credence.RuleHelpers.dsl_dropped_ranges(rule, ast, opts) do
          [] ->
            issues

          dropped ->
            Enum.reject(issues, &Credence.DslGuard.line_in_ranges?(&1.meta[:line], dropped))
        end
    end
  end

  @spec fix(String.t(), keyword()) :: String.t()
  def fix(code_string, opts \\ []) do
    {code, _applied} = fix_with_trace(code_string, opts)
    code
  end

  @doc """
  Like `fix/2`, but also returns a list of `{rule_module, issue_count}` tuples
  for every rule that actually fired and was applied.

  Every step is logged via `Logger.debug` with `[credence_fix]` prefix:
  rule name, issue count, whether the source changed, and a before/after
  diff of the lines that were modified.

  Pattern rules operate on the AST, so they need the source to *parse*, not to
  compile. A file that does not compile is still fixed — every fix just has to
  clear a higher bar: it may not add a compile error the source did not already
  have. See `Credence.RuleHelpers.compiles_no_worse?/2` for why that replaced
  skipping the round outright, and what it measured.
  """
  @spec fix_with_trace(String.t(), keyword()) ::
          {String.t(),
           [{module(), non_neg_integer() | :reverted | :patch_rejected | :crashed | :no_op}]}
  def fix_with_trace(code_string, opts \\ []) do
    all_rules = rules(opts)

    Logger.debug("[credence_fix] starting pattern fix pipeline (#{length(all_rules)} rules)")

    # The baseline: whatever was already broken about this file before the
    # Pattern round touched it. Empty when the source compiles, which is the
    # ordinary case and reduces every check below to the old `compiles?/1`.
    #
    # This used to be a gate — `if compiles?(code_string)`, else skip all 156
    # rules — and the cost of that was measured: 625 of 1,724 Pattern test
    # fixtures parse but do not compile, and 292 of those have a Pattern rule
    # firing that never ran. See `RuleHelpers.compiles_no_worse?/2`.
    baseline = RuleHelpers.compile_errors(code_string)

    if MapSet.size(baseline) > 0 do
      Logger.debug(
        "[credence_fix] source has #{MapSet.size(baseline)} pre-existing compile error(s); " <>
          "pattern fixes must not add to them"
      )
    end

    run_fixable_rules(all_rules, code_string, opts, baseline)
  end

  # The parse is threaded through the accumulator rather than redone per rule.
  # Of the seven ways out of this reduce, exactly ONE returns a different source
  # — the accepted-fix branch of `apply_or_revert/9` — so the parse is only ever
  # stale if that branch forgets to re-derive it, which is a single place to get
  # right rather than a cache with an invalidation window.
  #
  # It was 157 `Sourceror.parse_string/1` calls per file, one per rule, where a
  # file with five firing rules has only six distinct source strings. Sourceror's
  # parse is not cheap: `Code.string_to_quoted` with `literal_encoder`,
  # `token_metadata` and `columns`, then a full `Macro.traverse` to merge
  # comments back in.
  #
  # The re-derivation must go through `Sourceror.parse_string/1` and keep the
  # `{:error, _}` branch. `apply_rule_fix_with_status/3` only proved the output
  # satisfies `Code.string_to_quoted/1`, and Sourceror parses under a different
  # option set, so "it was accepted" is not "Sourceror can read it".
  defp run_fixable_rules(fixable, code_string, opts, baseline) do
    seed = {code_string, Sourceror.parse_string(code_string), [], baseline}

    {code, _parsed, applied, _baseline} =
      Enum.reduce(fixable, seed, fn rule, {source, parsed, applied, baseline} ->
        case parsed do
          {:ok, ast} ->
            check_opts = Keyword.put(opts, :source, source)
            issues = rule.check(ast, check_opts)

            if issues != [] do
              name = RuleHelpers.rule_name(rule)

              Logger.debug(
                "[credence_fix] #{name}: check found #{length(issues)} issue(s), running fix..."
              )

              case isolate(rule, :fix_patches, :crashed, fn ->
                     invoke_fix(rule, source, check_opts)
                   end) do
                :crashed ->
                  {source, parsed, [{rule, :crashed} | applied], baseline}

                {status, fixed} ->
                  apply_or_revert(
                    rule,
                    name,
                    source,
                    parsed,
                    fixed,
                    status,
                    issues,
                    applied,
                    baseline
                  )
              end
            else
              {source, parsed, applied, baseline}
            end

          {:error, reason} ->
            Logger.debug(
              "[credence_fix] source does not parse, no pattern rule can run: #{inspect(reason)}"
            )

            {source, parsed, applied, baseline}
        end
      end)

    applied = Enum.reverse(applied)

    summary =
      Enum.map_join(applied, ", ", fn {mod, count_or_status} ->
        "#{RuleHelpers.rule_name(mod)}(#{count_or_status})"
      end)

    Logger.debug("[credence_fix] done. Applied: [#{summary}]")

    {code, applied}
  end

  # C6. A rule's `check/2` and `fix_patches/2` run on AI-generated input, and a
  # rule that raises on one shape takes down the whole `analyze`/`fix` call with
  # it — every other rule's findings included. docs/09 records a shipped rule
  # raising `:erlang.length(nil)` on 36 corpus files.
  #
  # A crashing rule is a bug to fix, not a reason to lose the other 154 rules'
  # work. It is logged at `:error` with the stacktrace (this is never routine),
  # recorded as `{rule, :crashed}` in the trace so the harness's bugfix lane can
  # consume it alongside `:reverted` and `:patch_rejected`, and skipped.
  #
  # `Exception.blame/3` is deliberately not used: it is expensive and this path
  # is already the abnormal one, but more importantly it can itself raise on a
  # malformed stacktrace, which would defeat the isolation.
  defp isolate(rule, callback, on_crash, fun) do
    fun.()
  rescue
    e ->
      Logger.error(
        "[credence] #{RuleHelpers.rule_name(rule)}.#{callback} CRASHED — rule skipped for " <>
          "this source. This is a defect in the rule: #{Exception.message(e)}\n" <>
          Exception.format_stacktrace(__STACKTRACE__)
      )

      on_crash
  catch
    kind, value ->
      Logger.error(
        "[credence] #{RuleHelpers.rule_name(rule)}.#{callback} threw #{kind} #{inspect(value)} — " <>
          "rule skipped for this source. This is a defect in the rule."
      )

      on_crash
  end

  # Apply the rule's `fix_patches/2` to the source. See
  # `Credence.RuleHelpers.apply_rule_fix/3`.
  defp invoke_fix(rule, source, opts),
    do: RuleHelpers.apply_rule_fix_with_status(rule, source, opts)

  # Compile-output gate. A rule whose `fix/2` returns source that no
  # longer compiles would otherwise:
  #   - get propagated to the next rule (which then either crashes on
  #     parse or compounds the damage), or
  #   - be returned silently to the caller as a "successful" fix.
  # Instead we revert to the pre-fix source for that rule and mark
  # it as `:reverted` in the trace so the offending rule is visible.
  defp apply_or_revert(rule, name, source, parsed, fixed, status, issues, applied, baseline) do
    cond do
      # C5. Patches WERE produced and then discarded by the safety invariants in
      # `apply_rule_fix_with_status/3` (output did not parse, or the comment
      # multiset changed). The finding stands but goes unfixed — the one
      # exception to "every Pattern rule fixes what it finds". Without this
      # branch it is indistinguishable from a rule that had nothing to do:
      # `fixed == source` either way, nothing in the trace, nothing in the log.
      status == :patch_rejected ->
        Logger.warning(
          "[credence_fix] #{name}: patches produced but REJECTED by the safety " <>
            "invariants (non-parsing output or perturbed comments) — " <>
            "#{length(issues)} finding(s) reported and left unfixed"
        )

        {source, parsed, [{rule, :patch_rejected} | applied], baseline}

      # T3.2. The check fired and the fix changed nothing. Before this branch the
      # rule vanished from the trace entirely (a `Logger.debug` and no entry), so
      # it was indistinguishable from a rule that had nothing to do — the exact
      # invisibility C5 introduced `:patch_rejected` to end, one step earlier in
      # the pipeline: there the patches were produced and rejected, here they were
      # never produced at all. Both leave a reported finding unfixed, and the
      # harness's bugfix lane can only act on what the trace names.
      fixed == source ->
        Logger.warning(
          "[credence_fix] #{name}: check found #{length(issues)} issue(s) but fix returned " <>
            "IDENTICAL source — the finding is reported and left unfixed"
        )

        {source, parsed, [{rule, :no_op} | applied], baseline}

      # Everything below needs the output's compile errors, and everything above
      # must not pay for them: those two branches leave the source untouched and
      # compile nothing today. Splitting the decision out is what keeps that true
      # while still computing the error set exactly ONCE for the two consumers
      # that both want it — the revert test and the new baseline.
      true ->
        decide(rule, name, source, parsed, fixed, issues, applied, baseline)
    end
  end

  defp decide(rule, name, source, parsed, fixed, issues, applied, baseline) do
    errors = RuleHelpers.compile_errors(fixed)

    if MapSet.subset?(errors, baseline) do
      RuleHelpers.log_diff(name, source, fixed)

      # Re-baseline on the accepted output rather than carrying the original.
      # Keeping the original would be a hole: if this fix removed a pre-existing
      # error, a later rule could re-introduce it and still pass the subset test.
      # `errors` is that new baseline — already computed, not recompiled.
      {fixed, Sourceror.parse_string(fixed), [{rule, length(issues)} | applied], errors}
    else
      Logger.warning(
        "[credence_fix] #{name}: fix ADDED a compile error the source did not have, reverting"
      )

      # Visibility (Tunex `08` T1.3): log the broken before/after so a reverted
      # fix's diff lands in the row log for the deterministic bugfix-lane seed.
      RuleHelpers.log_diff(name, source, fixed)

      {source, parsed, [{rule, :reverted} | applied], baseline}
    end
  end

  # The base list always runs through the assumption filter — even when the
  # caller hands an explicit `rules:` list — so naming a rule can never punch
  # through the safety guarantee. `explicit?` lets the filter warn (not crash)
  # when a rule the caller named by hand gets filtered out.
  defp rules(opts) do
    {base, explicit?} =
      case Keyword.fetch(opts, :rules) do
        {:ok, list} -> {list, true}
        :error -> {default_rules(), false}
      end

    RuleHelpers.filter_by_assumptions(base, opts, explicit?)
  end

  @doc false
  def default_rules do
    RuleHelpers.discover_rules(Credence.Pattern.Rule)
  end

  @doc """
  Returns the status of every rule Credence found (or every rule in an explicit
  `rules:` list), as maps with:

  - `:rule` — the rule module
  - `:name` — its short name
  - `:assumptions` — the promises it needs
  - `:enabled` — whether all of them are on under `opts` right now
  - `:missing` — which needed promises are off

  Honours the same `assumptions:` / `config :credence` settings as `fix/2`, so
  this is the place to answer "what did I promise, and why didn't this rule fire?"
  """
  @spec rule_status(keyword()) :: [
          %{
            rule: module(),
            name: String.t(),
            assumptions: [atom()],
            enabled: boolean(),
            missing: [atom()]
          }
        ]
  def rule_status(opts \\ []) do
    effective = RuleHelpers.effective_assumptions(opts)
    base = Keyword.get(opts, :rules, default_rules())

    Enum.map(base, fn rule ->
      missing = RuleHelpers.missing_assumptions(rule, effective)

      %{
        rule: rule,
        name: RuleHelpers.rule_name(rule),
        assumptions: rule.assumptions(),
        enabled: missing == [],
        missing: missing
      }
    end)
  end

  @doc """
  The short names of the rules that are on under `opts`. Derived from
  `rule_status/1` so the two answers never disagree.
  """
  @spec enabled_rules(keyword()) :: [String.t()]
  def enabled_rules(opts \\ []) do
    opts |> rule_status() |> Enum.filter(& &1.enabled) |> Enum.map(& &1.name)
  end

  defp parse_error_issue(line, error_msg, token) do
    # parse errors carry either a binary message or an {opening, hint} tuple
    error_str =
      case error_msg do
        msg when is_binary(msg) -> msg
        {opening, hint} when is_binary(opening) and is_binary(hint) -> opening <> "..." <> hint
        other -> inspect(other)
      end

    %Credence.Issue{
      rule: :parse_error,
      message: "Syntax error: #{error_str} at token #{inspect(token)}",
      meta: %{line: line}
    }
  end
end
