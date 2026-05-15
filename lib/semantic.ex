defmodule Credence.Semantic do
  @moduledoc """
  Semantic phase — fixes compiler warnings and errors.

  Uses `Code.with_diagnostics/1` to compile the source and capture
  diagnostics without permanently loading modules. Delegates to rules
  implementing `Credence.Semantic.Rule` behaviour.

  When compilation succeeds, warning-level diagnostics are matched
  against rules and fixed. When compilation fails, error-level
  diagnostics are matched first; if any fix is applied, the phase
  retries (up to `max_passes`) to catch warnings that only appear
  once the error is resolved.
  """

  require Logger
  alias Credence.RuleHelpers

  @default_max_passes 3

  @spec analyze(String.t(), keyword()) :: [Credence.Issue.t()]
  def analyze(source, _opts \\ []) do
    case RuleHelpers.compile_and_capture(source) do
      {:ok, diagnostics} ->
        diagnostics
        |> Enum.filter(&(&1.severity == :warning))
        |> Enum.flat_map(&match_rules/1)

      {:error, diagnostics} ->
        diagnostics
        |> Enum.filter(&(&1.severity == :error))
        |> Enum.flat_map(&match_rules/1)
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
  pass number, severity being targeted, rule name, whether the source
  changed, and a before/after diff of the lines that were modified.
  """
  @spec fix_with_trace(String.t(), keyword()) ::
          {String.t(), [{module(), non_neg_integer()}]}
  def fix_with_trace(source, opts \\ []) do
    max_passes = Keyword.get(opts, :max_passes, @default_max_passes)

    Logger.debug(
      "[credence_fix] starting semantic fix pipeline (max #{max_passes} passes, #{length(rules())} rules)"
    )

    {code, applied} = do_fix_traced(source, max_passes, 1, [])

    summary =
      Enum.map_join(applied, ", ", fn {mod, count} ->
        "#{RuleHelpers.rule_name(mod)}(#{count})"
      end)

    Logger.debug("[credence_fix] semantic done. Applied: [#{summary}]")

    {code, applied}
  end

  defp do_fix_traced(source, max_passes, pass, applied) when pass > max_passes do
    Logger.debug("[credence_fix] semantic pass limit reached (#{max_passes}), stopping")
    {source, Enum.reverse(applied)}
  end

  defp do_fix_traced(source, max_passes, pass, applied) do
    case RuleHelpers.compile_and_capture(source) do
      {:ok, diagnostics} ->
        # Compilation succeeded — fix warnings (terminal pass, no retry needed)
        warnings = Enum.filter(diagnostics, &(&1.severity == :warning))

        Logger.debug(
          "[credence_fix] semantic pass #{pass}: compilation OK, #{length(warnings)} warning(s)"
        )

        {fixed, new_applied} = apply_fixes_traced(source, warnings)
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

        {fixed, new_applied} = apply_fixes_traced(source, errors)

        if fixed != source do
          Logger.debug("[credence_fix] semantic pass #{pass}: source changed, retrying...")
          do_fix_traced(fixed, max_passes, pass + 1, new_applied ++ applied)
        else
          Logger.debug(
            "[credence_fix] semantic pass #{pass}: no rule could fix the error(s), stopping"
          )

          {fixed, Enum.reverse(new_applied ++ applied)}
        end
    end
  end

  defp apply_fixes_traced(source, diagnostics) do
    Enum.reduce(diagnostics, {source, []}, fn diagnostic, {src, applied} ->
      case find_matching_rule(diagnostic) do
        nil ->
          Logger.debug(
            "[credence_fix] no rule matched diagnostic: #{inspect(diagnostic.message)}"
          )

          {src, applied}

        rule ->
          name = RuleHelpers.rule_name(rule)

          Logger.debug("[credence_fix] #{name}: matched diagnostic, running fix...")

          fixed = rule.fix(src, diagnostic)

          if fixed == src do
            Logger.debug("[credence_fix] #{name}: fix returned IDENTICAL source (no change)")
          else
            RuleHelpers.log_diff(name, src, fixed)
          end

          {fixed, [{rule, 1} | applied]}
      end
    end)
  end

  defp match_rules(diagnostic) do
    case find_matching_rule(diagnostic) do
      nil -> []
      rule -> [rule.to_issue(diagnostic)]
    end
  end

  defp find_matching_rule(diagnostic) do
    Enum.find(rules(), fn rule -> rule.match?(diagnostic) end)
  end

  defp rules do
    RuleHelpers.discover_rules(Credence.Semantic.Rule)
  end
end
