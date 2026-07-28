defmodule Credence.Syntax do
  @moduledoc """
  Syntax phase — fixes code that won't parse.

  Only runs when `Sourceror.parse_string/1` fails. Delegates to rules
  implementing `Credence.Syntax.Rule` behaviour.

  Rules are discovered automatically and run in priority order (lower first),
  with module name as tiebreaker for determinism.

  ## Round safety (docs/12 `C3`)

  Syntax rules are raw string→string rewrites over source the parser has already
  rejected, so the round cannot fall back on an AST to keep them honest. Two
  guards wrap the reduce:

    * **Per-rule progress guard.** A rule's output is kept unless it made the
      source demonstrably *worse* — see `Credence.Syntax.ProgressGuard`. A
      regression is reverted and recorded as `{rule, :reverted}`, mirroring the
      Pattern round's discipline. "Still does not parse" is **not** a
      regression: this round exists to walk through unparseable intermediate
      states, and gating on "must parse now" would disable it.

    * **Phase-level all-or-nothing.** If the source still does not parse once
      every rule has run, the round returns the **original** input rather than a
      half-rewritten one, and every kept change is downgraded to
      `{rule, :rolled_back}` in the trace. Pass `syntax_partial_repairs: true`
      to opt out and receive the partial repair (a caller that wants it as a
      retry signal).

  ## Options

    * `:syntax_rules` — run this exact rule list instead of the discovered one.
      Deliberately not `:rules` (that key belongs to the Pattern round, and a
      caller passing Pattern rules to `Credence.fix/2` must not have them
      handed to this round as well).
    * `:syntax_partial_repairs` — see above. Defaults to `false`.
  """

  require Logger
  alias Credence.RuleHelpers
  alias Credence.Syntax.ProgressGuard

  @spec analyze(String.t(), keyword()) :: [Credence.Issue.t()]
  def analyze(source, opts \\ []) do
    case Sourceror.parse_string(source) do
      {:ok, _ast} -> []
      {:error, _} -> Enum.flat_map(rules(opts), & &1.analyze(source))
    end
  end

  @spec fix(String.t(), keyword()) :: String.t()
  def fix(source, opts \\ []) do
    {code, _applied} = fix_with_trace(source, opts)
    code
  end

  @doc """
  Like `fix/2`, but also returns a list of `{rule_module, issue_count}` tuples
  for every rule that actually fired and was applied.

  A rule whose output was rejected by the progress guard appears as
  `{rule, :reverted}`; if the whole round was rolled back because the result
  still does not parse, every kept change appears as `{rule, :rolled_back}` and
  the returned source is the untouched original.

  Every step is logged via `Logger.debug` with `[credence_fix]` prefix:
  rule name, whether the source changed, and a before/after diff of the
  lines that were modified. If the source already parses, the pipeline
  is skipped entirely.
  """
  @spec fix_with_trace(String.t(), keyword()) ::
          {String.t(), [{module(), non_neg_integer() | :reverted | :rolled_back}]}
  def fix_with_trace(source, opts \\ []) do
    all_rules = rules(opts)

    case Sourceror.parse_string(source) do
      {:ok, _ast} ->
        Logger.debug("[credence_fix] syntax fix pipeline: source already parses, skipping")
        {source, []}

      {:error, {meta, error_msg, token}} ->
        Logger.debug(
          "[credence_fix] starting syntax fix pipeline (#{length(all_rules)} rules), " <>
            describe_error(meta, error_msg, token)
        )

        {fixed, applied, _state} =
          Enum.reduce(all_rules, {source, [], ProgressGuard.measure(source)}, &run_rule/2)

        {code, applied} = commit_or_roll_back(source, fixed, Enum.reverse(applied), opts)

        summary =
          Enum.map_join(applied, ", ", fn {mod, count} ->
            "#{RuleHelpers.rule_name(mod)}(#{count})"
          end)

        Logger.debug("[credence_fix] syntax done. Applied: [#{summary}]")

        {code, applied}
    end
  end

  # The progress guard, per rule. The round's input never parses and its
  # intermediate states are expected not to parse either, so the only thing a
  # rule can be held to is that it did not move the front end *backwards*:
  # source that tokenized must still tokenize, and a parse error must not
  # retreat above the text this rule rewrote. See `Credence.Syntax.ProgressGuard`.
  defp run_rule(rule, {src, applied, state}) do
    name = RuleHelpers.rule_name(rule)
    result = rule.fix(src)

    if result == src do
      {src, applied, state}
    else
      result_state = ProgressGuard.measure(result)

      case ProgressGuard.verdict(src, state, result, result_state) do
        :keep ->
          Logger.debug("[credence_fix] #{name}: fix produced a change")

          RuleHelpers.log_diff(name, src, result)
          {result, [{rule, 1} | applied], result_state}

        :revert ->
          Logger.warning(
            "[credence_fix] #{name}: fix made the source WORSE " <>
              "(#{ProgressGuard.describe(state)} → #{ProgressGuard.describe(result_state)}), " <>
              "reverting"
          )

          # Log the rejected before/after so the offending rewrite lands in the
          # row log for the deterministic bugfix lane, as Pattern does.
          RuleHelpers.log_diff(name, src, result)
          {src, [{rule, :reverted} | applied], state}
      end
    end
  end

  # All-or-nothing. A round that ends on source the parser still rejects has
  # produced, at best, an unverifiable partial rewrite: no later phase can look
  # at it (Semantic needs it to compile, Pattern needs it to parse), and Phase 4
  # found live rules whose partial output was outright corrupt. Returning the
  # original keeps the caller's failure loud and located instead of shipping a
  # half-rewritten file that merely *looks* repaired.
  defp commit_or_roll_back(source, fixed, applied, opts) do
    case Sourceror.parse_string(fixed) do
      {:ok, _} ->
        Logger.debug("[credence_fix] syntax fix pipeline: source now parses successfully")
        {fixed, applied}

      {:error, {meta, error_msg, token}} ->
        Logger.debug(
          "[credence_fix] syntax fix pipeline: source still does not parse " <>
            "(#{describe_error(meta, error_msg, token)})"
        )

        roll_back(source, fixed, applied, opts)
    end
  end

  defp roll_back(source, fixed, applied, opts) do
    kept = Enum.count(applied, fn {_rule, status} -> is_integer(status) end)

    cond do
      kept == 0 ->
        {source, applied}

      Keyword.get(opts, :syntax_partial_repairs, false) ->
        Logger.debug(
          "[credence_fix] syntax fix pipeline: keeping #{kept} partial change(s) " <>
            "(syntax_partial_repairs: true)"
        )

        {fixed, applied}

      true ->
        Logger.debug(
          "[credence_fix] syntax fix pipeline: DISCARDING #{kept} change(s) and returning " <>
            "the original source (all-or-nothing)"
        )

        {source, Enum.map(applied, &roll_back_entry/1)}
    end
  end

  defp roll_back_entry({rule, status}) when is_integer(status), do: {rule, :rolled_back}
  defp roll_back_entry(entry), do: entry

  # Parse errors carry either a binary message or an `{opening, hint}` tuple
  # (e.g. "unexpected reserved word" guidance) — interpolating the tuple raised.
  defp describe_error(meta, error_msg, token) do
    error_str =
      case error_msg do
        msg when is_binary(msg) ->
          msg

        {opening, hint} when is_binary(opening) and is_binary(hint) ->
          opening <> "..." <> hint

        other ->
          inspect(other)
      end

    "parse error at line #{Keyword.get(meta, :line)}: #{error_str} near #{inspect(token)}"
  end

  @doc false
  def default_rules do
    RuleHelpers.discover_rules(Credence.Syntax.Rule)
  end

  # `:syntax_rules`, not `:rules`: `Credence.fix/2` forwards one opts list to all
  # three rounds, and `:rules` there means "these Pattern rules".
  defp rules(opts), do: Keyword.get(opts, :syntax_rules, default_rules())
end
