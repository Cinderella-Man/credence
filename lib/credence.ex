defmodule Credence do
  @moduledoc """
  Credence (Semantic Linter for Elixir)
  Main entry point for analyzing Elixir code.
  """
  alias Credence.Issue

  # The default profile of rules to run
  @default_rules [
    Credence.Rule.NoDoubleSortSameList,
    Credence.Rule.NoGraphemePalindromeCheck,
    Credence.Rule.NoGuardEqualityForPatternMatch,
    Credence.Rule.NoLengthInGuard,
    Credence.Rule.NoListAppendInLoop,
    Credence.Rule.NoListLast,
    Credence.Rule.NoManualStringReverse,
    Credence.Rule.NoMultipleEnumAt,
    Credence.Rule.NoParamRebinding,
    Credence.Rule.NoRedundantEnumJoinSeparator,
    Credence.Rule.NoSortThenAt,
    Credence.Rule.NoSortThenReverse,
    Credence.Rule.NoStringLengthForCharCheck
  ]

  @doc """
  Analyzes an Elixir code string and returns a deterministic pass/fail result.
  """
  @spec analyze(String.t(), keyword()) :: %{valid: boolean(), issues: [Issue.t()]}
  def analyze(code_string, opts \\ []) do
    rules = Keyword.get(opts, :rules, @default_rules)

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
end
