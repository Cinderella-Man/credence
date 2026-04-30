defmodule Credence do
  @moduledoc """
  Credence (Semantic Linter for Elixir)
  Main entry point for analyzing Elixir code.
  """
  alias Credence.Issue

  @doc """
  Analyzes an Elixir code string and returns a deterministic pass/fail result.
  """
  @spec analyze(String.t(), keyword()) :: %{valid: boolean(), issues: [Issue.t()]}
  def analyze(code_string, opts \\ []) do
    rules = Keyword.get(opts, :rules, default_rules())

    case Code.string_to_quoted(code_string) do
      {:ok, ast} ->
        issues = run_rules(ast, rules, opts)

        %{
          valid: Enum.empty?(issues),
          issues: issues
        }

      {:error, {line, error_msg, token}} ->
        # Fails gracefully by returning the parse error as a critical issue
        %{
          valid: false,
          issues: [
            %Issue{
              rule: :parse_error,
              severity: :critical,
              message: "Syntax error: #{error_msg} at token #{inspect(token)}",
              meta: %{line: line}
            }
          ]
        }
    end
  end

  defp run_rules(ast, rules, opts) do
    Enum.flat_map(rules, fn rule ->
      rule.check(ast, opts)
    end)
  end

  defp default_rules do
    :code.all_loaded()
    |> Enum.map(fn {module, _} -> module end)
    |> Enum.filter(fn module ->
      # 1. Ensure it's an Elixir module (Erlang modules don't have __info__/1)
      if function_exported?(module, :__info__, 1) do
        attributes = module.__info__(:attributes)
        behaviours = Keyword.get(attributes, :behaviour, [])

        # 2. Check if your Rule behaviour is in the list
        Credence.Rule in behaviours
      else
        false
      end
    end)
  end
end
