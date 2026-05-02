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
        %{valid: Enum.empty?(issues), issues: issues}

      {:error, {line, error_msg, token}} ->
        %{valid: false, issues: [parse_error_issue(line, error_msg, token)]}
    end
  end

  @doc """
  Auto-fixes all fixable issues in the given code string.

  Pipes the source through each fixable rule's `fix/2` in sequence,
  then re-analyzes to report any remaining (unfixable) issues.
  """
  @spec fix(String.t(), keyword()) :: %{code: String.t(), issues: [Issue.t()]}
  def fix(code_string, opts \\ []) do
    rules = Keyword.get(opts, :rules, default_rules())
    {fixable, _unfixable} = Enum.split_with(rules, & &1.fixable?())

    fixed_code =
      Enum.reduce(fixable, code_string, fn rule, source ->
        rule.fix(source, opts)
      end)

    %{issues: remaining} = analyze(fixed_code, opts)

    %{code: fixed_code, issues: remaining}
  end

  defp run_rules(ast, rules, opts) do
    Enum.flat_map(rules, & &1.check(ast, opts))
  end

  defp default_rules do
    Application.spec(:credence, :modules)
    |> Enum.filter(fn module ->
      Credence.Rule in Keyword.get(module.__info__(:attributes), :behaviour, [])
    end)
  end

  defp parse_error_issue(line, error_msg, token) do
    %Issue{
      rule: :parse_error,
      message: "Syntax error: #{error_msg} at token #{inspect(token)}",
      meta: %{line: line}
    }
  end
end
