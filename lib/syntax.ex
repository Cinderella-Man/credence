defmodule Credence.Syntax do
  @moduledoc """
  Syntax phase — fixes code that won't parse.

  Only runs when `Sourceror.parse_string/1` fails. Delegates to rules
  implementing `Credence.Syntax.Rule` behaviour.

  Rules are discovered automatically and run in priority order (lower first),
  with module name as tiebreaker for determinism.
  """

  require Logger
  alias Credence.RuleHelpers

  @spec analyze(String.t(), keyword()) :: [Credence.Issue.t()]
  def analyze(source, _opts \\ []) do
    # Run syntax rules on all source — structural issues can exist even
    # when the source parses (e.g. module attributes outside defmodule).
    Enum.flat_map(rules(), & &1.analyze(source))
  end

  @spec fix(String.t(), keyword()) :: String.t()
  def fix(source, opts \\ []) do
    {code, _applied} = fix_with_trace(source, opts)
    code
  end

  @doc """
  Like `fix/2`, but also returns a list of `{rule_module, issue_count}` tuples
  for every rule that actually fired and was applied.

  Every step is logged via `Logger.debug` with `[credence_fix]` prefix:
  rule name, whether the source changed, and a before/after diff of the
  lines that were modified. If the source already parses, the pipeline
  is skipped entirely.
  """
  @spec fix_with_trace(String.t(), keyword()) ::
          {String.t(), [{module(), non_neg_integer()}]}
  def fix_with_trace(source, _opts \\ []) do
    all_rules = rules()

    case Sourceror.parse_string(source) do
      {:ok, _ast} ->
        # Source parses, but still run rules for structural fixes
        # (e.g. module attributes outside module, stale access modifiers)
        {fixed, applied} = apply_rules_traced(all_rules, source)

        if fixed == source do
          Logger.debug("[credence_fix] syntax fix pipeline: source already parses, no fixes needed")
        else
          Logger.debug("[credence_fix] syntax fix pipeline: applied structural fixes")
        end

        {fixed, applied}

      {:error, {meta, error_msg, token}} ->
        line = Keyword.get(meta, :line)

        Logger.debug(
          "[credence_fix] starting syntax fix pipeline (#{length(all_rules)} rules), " <>
            "parse error at line #{line}: #{error_msg} near #{inspect(token)}"
        )

        {fixed, applied} = apply_rules_traced(all_rules, source)

        # Verify fix actually helped
        case Sourceror.parse_string(fixed) do
          {:ok, _} ->
            Logger.debug("[credence_fix] syntax fix pipeline: source now parses successfully")

          {:error, {meta, error_msg, token}} ->
            line = Keyword.get(meta, :line)

            Logger.debug(
              "[credence_fix] syntax fix pipeline: source still does not parse " <>
                "(line #{line}: #{error_msg} near #{inspect(token)})"
            )
        end

        summary =
          Enum.map_join(applied, ", ", fn {mod, count} ->
            "#{RuleHelpers.rule_name(mod)}(#{count})"
          end)

        Logger.debug("[credence_fix] syntax done. Applied: [#{summary}]")

        {fixed, applied}
    end
  end

  defp apply_rules_traced(all_rules, source) do
    {fixed, applied} =
      Enum.reduce(all_rules, {source, []}, fn rule, {src, applied} ->
        name = RuleHelpers.rule_name(rule)
        result = rule.fix(src)

        if result == src do
          {src, applied}
        else
          Logger.debug("[credence_fix] #{name}: fix produced a change")

          RuleHelpers.log_diff(name, src, result)
          {result, [{rule, 1} | applied]}
        end
      end)

    {fixed, Enum.reverse(applied)}
  end

  defp rules do
    RuleHelpers.discover_rules(Credence.Syntax.Rule)
  end
end
