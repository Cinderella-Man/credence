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

  alias Credence.RuleHelpers

  @default_max_passes 3

  @spec analyze(String.t(), keyword()) :: [Credence.Issue.t()]
  def analyze(source, _opts \\ []) do
    case compile_and_capture(source) do
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
    max_passes = Keyword.get(opts, :max_passes, @default_max_passes)
    do_fix(source, max_passes)
  end

  defp do_fix(source, 0), do: source

  defp do_fix(source, passes_remaining) do
    case compile_and_capture(source) do
      {:ok, diagnostics} ->
        # Compilation succeeded — fix warnings (terminal pass, no retry needed)
        apply_fixes(source, diagnostics, :warning)

      {:error, diagnostics} ->
        # Compilation failed — fix errors, then retry
        fixed = apply_fixes(source, diagnostics, :error)

        if fixed != source do
          do_fix(fixed, passes_remaining - 1)
        else
          # No rule could fix the error — return as-is
          fixed
        end
    end
  end

  defp apply_fixes(source, diagnostics, severity) do
    diagnostics
    |> Enum.filter(&(&1.severity == severity))
    |> Enum.reduce(source, fn diagnostic, src ->
      case find_matching_rule(diagnostic) do
        nil -> src
        rule -> rule.fix(src, diagnostic)
      end
    end)
  end

  defp compile_and_capture(source) do
    {result, diagnostics} =
      Code.with_diagnostics(fn ->
        try do
          Code.compile_string(source, "credence_check.ex")
        rescue
          _ -> :error
        end
      end)

    case result do
      :error ->
        {:error, diagnostics}

      modules when is_list(modules) ->
        cleanup_modules(modules)
        {:ok, diagnostics}
    end
  end

  defp cleanup_modules(modules) do
    for {mod, _binary} <- modules do
      :code.purge(mod)
      :code.delete(mod)
    end
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
