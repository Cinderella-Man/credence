defmodule Credence do
  @moduledoc """
  Credence — Semantic Linter for Elixir.

  Routes analysis and fixing through three phases:

  1. **Syntax** — string-level fixes for syntax errors that prevent parsing
     (e.g. `expr div expr` infix syntax from Python translations)
  2. **Semantic** — fixes for compiler warnings like unused variables
     and undefined function references
  3. **Pattern** — AST-level anti-pattern rules (the bulk of Credence)

  Both `analyze/2` and `fix/2` accept a source string and options.
  `analyze` detects issues without modifying code (stops if code won't parse).
  `fix` repairs what it can, then re-analyzes for remaining issues.
  """
  alias Credence.Issue

  @doc """
  Analyzes an Elixir code string and returns a deterministic pass/fail result.

  Runs all three phases. If the code has syntax errors that PreCompile detects,
  analysis stops there (later phases need parseable code).
  """
  @spec analyze(String.t(), keyword()) :: %{valid: boolean(), issues: [Issue.t()]}
  def analyze(code_string, opts \\ []) do
    pre_issues = Credence.Syntax.analyze(code_string, opts)

    if has_blocking_issues?(pre_issues) do
      %{valid: false, issues: pre_issues}
    else
      compiler_issues = Credence.Semantic.analyze(code_string, opts)
      post_issues = Credence.Pattern.analyze(code_string, opts)

      all_issues = compiler_issues ++ post_issues
      %{valid: Enum.empty?(all_issues), issues: all_issues}
    end
  end

  @doc """
  Auto-fixes all fixable issues in the given code string.

  Pipes the source through Syntax → Semantic → Pattern fixers,
  then re-analyzes to report any remaining (unfixable) issues.
  """
  @spec fix(String.t(), keyword()) :: %{code: String.t(), issues: [Issue.t()]}
  def fix(code_string, opts \\ []) do
    fixed =
      code_string
      |> Credence.Syntax.fix(opts)
      |> Credence.Semantic.fix(opts)
      |> Credence.Pattern.fix(opts)

    %{issues: remaining} = analyze(fixed, Keyword.put(opts, :source, fixed))
    %{code: fixed, issues: remaining}
  end

  # Syntax issues are blocking — code can't parse, so later phases can't run
  defp has_blocking_issues?(issues) do
    Enum.any?(issues)
  end
end
