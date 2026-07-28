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
  alias Credence.RuleHelpers

  @type rule_status_entry :: %{
          round: :syntax | :semantic | :pattern,
          rule: module(),
          name: String.t(),
          assumptions: [atom()],
          enabled: boolean(),
          missing: [atom()]
        }

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

  @typedoc """
  What a round did with one rule: how many findings it fixed, or why its output
  is not in the returned code — `:reverted` (the rule made things worse),
  `:rolled_back` (the Syntax round discarded every change because the result
  still did not parse), `:patch_rejected` (the patch broke a safety invariant)
  or `:crashed`.
  """
  @type rule_outcome ::
          non_neg_integer() | :reverted | :rolled_back | :patch_rejected | :crashed

  @spec fix(String.t(), keyword()) :: %{
          code: String.t(),
          issues: [Issue.t()],
          applied_rules: [{module(), rule_outcome()}]
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

  @doc """
  Reports which rules would run for the given `opts`, across all three rounds,
  **without running them** — the opts-only counterpart to `fix/2`.

  Returns one entry per rule, in execution order (Syntax → Semantic → Pattern),
  each a map with:

    - `:round` — `:syntax`, `:semantic`, or `:pattern`
    - `:rule` — the rule module
    - `:name` — its short name
    - `:assumptions` — the promises it needs (always `[]` for Syntax/Semantic)
    - `:enabled` — whether it is eligible under `opts`
    - `:missing` — the needed promises that are off

  Only the Pattern round is opts-filtered — by `:assumptions` and an explicit
  `:rules` list (see `Credence.Pattern.rule_status/1`). Syntax and Semantic
  rules are never opts-filtered, so every discovered rule comes back
  `enabled: true`. Whether a rule *actually fires* further depends on the code
  itself — Syntax only runs when the source won't parse, Semantic only on the
  compiler diagnostics it matches — which this opts-only view does not inspect.
  """
  @spec rule_status(keyword()) :: [rule_status_entry()]
  def rule_status(opts \\ []) do
    unfiltered_entries(:syntax, Credence.Syntax.default_rules()) ++
      unfiltered_entries(:semantic, Credence.Semantic.default_rules()) ++
      Enum.map(Credence.Pattern.rule_status(opts), &Map.put(&1, :round, :pattern))
  end

  defp unfiltered_entries(round, rules) do
    Enum.map(rules, fn rule ->
      %{
        round: round,
        rule: rule,
        name: RuleHelpers.rule_name(rule),
        assumptions: [],
        enabled: true,
        missing: []
      }
    end)
  end

  @doc """
  The short names of every rule that would run under `opts`, across all three
  rounds, in execution order. Derived from `rule_status/1` so the two answers
  never disagree.
  """
  @spec enabled_rules(keyword()) :: [String.t()]
  def enabled_rules(opts \\ []) do
    opts |> rule_status() |> Enum.filter(& &1.enabled) |> Enum.map(& &1.name)
  end
end
