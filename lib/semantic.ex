defmodule Credence.Semantic do
  @moduledoc """
  Semantic phase — fixes compiler warnings.

  Uses `Code.with_diagnostics/1` to compile the source and capture
  warnings without permanently loading modules. Delegates to rules
  implementing `Credence.Semantic.Rule` behaviour.
  """

  @spec analyze(String.t(), keyword()) :: [Credence.Issue.t()]
  def analyze(source, _opts \\ []) do
    case compile_and_capture(source) do
      {:ok, diagnostics} ->
        diagnostics
        |> Enum.filter(&(&1.severity == :warning))
        |> Enum.flat_map(&match_rules/1)

      _error ->
        []
    end
  end

  @spec fix(String.t(), keyword()) :: String.t()
  def fix(source, _opts \\ []) do
    case compile_and_capture(source) do
      {:ok, diagnostics} ->
        warnings = Enum.filter(diagnostics, &(&1.severity == :warning))

        Enum.reduce(warnings, source, fn diagnostic, src ->
          case find_matching_rule(diagnostic) do
            nil -> src
            rule -> rule.fix(src, diagnostic)
          end
        end)

      _error ->
        source
    end
  end

  # ── Compilation ─────────────────────────────────────────────────

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

  # ── Rule dispatch ───────────────────────────────────────────────

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
    Application.spec(:credence, :modules)
    |> Enum.filter(&implements?(&1, Credence.Semantic.Rule))
    |> Enum.sort_by(&{&1.priority(), &1})
  end

  defp implements?(module, behaviour) do
    behaviour in Keyword.get(module.__info__(:attributes), :behaviour, [])
  end
end
