defmodule Credence do
  @moduledoc """
  Credence — Semantic Linter for Elixir.

  Routes analysis and fixing through three phases:

  1. **Syntax** — string-level fixes for code that won't parse
  2. **Semantic** — fixes for compiler warnings (unused vars, undefined fns)
  3. **Pattern** — AST-level anti-pattern rules (the bulk of Credence)

  Each phase has its own `Rule` behaviour and discovers rules automatically.
  """
  alias Credence.Issue

  @spec analyze(String.t(), keyword()) :: %{valid: boolean(), issues: [Issue.t()]}
  def analyze(code_string, opts \\ []) do
    syntax_issues = Credence.Syntax.analyze(code_string, opts)

    if Enum.any?(syntax_issues) do
      %{valid: false, issues: syntax_issues}
    else
      semantic_issues = Credence.Semantic.analyze(code_string, opts)
      pattern_issues = Credence.Pattern.analyze(code_string, opts)

      all_issues = semantic_issues ++ pattern_issues
      %{valid: Enum.empty?(all_issues), issues: all_issues}
    end
  end

  @spec fix(String.t(), keyword()) :: %{
          code: String.t(),
          issues: [Issue.t()],
          applied_rules: [{module(), non_neg_integer()}]
        }
  def fix(code_string, opts \\ []) do
    # Phase 1: Syntax (with trace)
    {after_syntax, syntax_applied} = Credence.Syntax.fix_with_trace(code_string, opts)

    # Phase 2: Semantic (with trace)
    {after_semantic, semantic_applied} = Credence.Semantic.fix_with_trace(after_syntax, opts)

    # Phase 3: Pattern (with trace)
    {fixed, pattern_applied} = Credence.Pattern.fix_with_trace(after_semantic, opts)

    all_applied = syntax_applied ++ semantic_applied ++ pattern_applied
    %{issues: remaining} = analyze(fixed, Keyword.put(opts, :source, fixed))
    %{code: fixed, issues: remaining, applied_rules: all_applied}
  end
end
