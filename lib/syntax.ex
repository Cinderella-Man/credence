defmodule Credence.Syntax do
  @moduledoc """
  Syntax phase — fixes code that won't parse.

  Only runs when `Code.string_to_quoted/1` fails. Delegates to rules
  implementing `Credence.Syntax.Rule` behaviour.

  Rules are discovered automatically and run in priority order (lower first),
  with module name as tiebreaker for determinism.
  """

  require Logger
  alias Credence.RuleHelpers

  @spec analyze(String.t(), keyword()) :: [Credence.Issue.t()]
  def analyze(source, _opts \\ []) do
    case Code.string_to_quoted(source) do
      {:ok, _ast} -> []
      {:error, _} -> Enum.flat_map(rules(), & &1.analyze(source))
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

  Every step is logged via `Logger.debug` with `[credence_fix]` prefix:
  rule name, whether the source changed, and a before/after diff of the
  lines that were modified. If the source already parses, the pipeline
  is skipped entirely.
  """
  @spec fix_with_trace(String.t(), keyword()) ::
          {String.t(), [{module(), non_neg_integer()}]}
  def fix_with_trace(source, _opts \\ []) do
    all_rules = rules()

    case Code.string_to_quoted(source) do
      {:ok, _ast} ->
        Logger.debug("[credence_fix] syntax fix pipeline: source already parses, skipping")
        {source, []}

      {:error, {line, error_msg, token}} ->
        Logger.debug(
          "[credence_fix] starting syntax fix pipeline (#{length(all_rules)} rules), " <>
            "parse error at line #{line}: #{error_msg} near #{inspect(token)}"
        )

        {fixed, applied} =
          Enum.reduce(all_rules, {source, []}, fn rule, {src, applied} ->
            name = RuleHelpers.rule_name(rule)
            result = rule.fix(src)

            if result == src do
              {src, applied}
            else
              Logger.debug(
                "[credence_fix] #{name}: fix produced a change"
              )

              RuleHelpers.log_diff(name, src, result)
              {result, [{rule, 1} | applied]}
            end
          end)

        applied = Enum.reverse(applied)

        # Verify fix actually helped
        case Code.string_to_quoted(fixed) do
          {:ok, _} ->
            Logger.debug("[credence_fix] syntax fix pipeline: source now parses successfully")

          {:error, {line, error_msg, token}} ->
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

  defp rules do
    RuleHelpers.discover_rules(Credence.Syntax.Rule)
  end
end
