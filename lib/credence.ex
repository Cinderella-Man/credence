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
          priority: integer(),
          unsafe_in_dsl: [atom()] | :all | nil,
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
  still did not parse), `:patch_rejected` (the patch broke a safety invariant),
  `:no_op` (the check fired and the fix returned identical source) or
  `:crashed`.

  This is a **closed set, and a cross-repo contract**. The evolution harness
  parses these atoms out of the `APPLIED_RULES:` line to build the closed set its
  classifier is allowed to name; an outcome its regex does not recognise is not
  an error there but a silent *drop*, which removes the rule from that set and
  makes a correct bug report about it unfileable. Adding a member here means
  widening `Cev.AppliedRules` in the same change — `test/applied_rules_contract_test.exs`
  pins the vocabulary on this side so the two cannot drift apart unnoticed.
  """
  @type rule_outcome ::
          non_neg_integer() | :reverted | :rolled_back | :patch_rejected | :crashed | :no_op

  @doc """
  The closed set of non-numeric `t:rule_outcome/0` atoms, as data.

  Exposed so the contract test — and the harness, which must accept every one of
  them — can enumerate the vocabulary rather than restate it. A numeric outcome
  (how many findings the rule fixed) is the other half and is not listed here.
  """
  @spec rule_outcomes() :: [atom()]
  def rule_outcomes, do: [:reverted, :rolled_back, :patch_rejected, :crashed, :no_op]

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
    %{code: fixed, issues: remaining_issues(fixed, opts), applied_rules: all_applied}
  end

  # The trailing analysis is a COMPLETE second pass — a compile for the Semantic
  # round plus a parse and all 156 `check/2` walks for the Pattern round — and it
  # roughly doubles the cost of `fix/2` for a caller that only wants `:code` and
  # `:applied_rules`. Both in-repo mix tasks are exactly such callers.
  #
  # Opt-OUT rather than opt-in, deliberately: `:issues` is a documented field of
  # the returned map (see the README), so the default has to keep answering it.
  # A caller that passes `analyze_after: false` is saying it will not read the
  # field, and gets `[]` — not a silently stale answer.
  defp remaining_issues(fixed, opts) do
    if Keyword.get(opts, :analyze_after, true) do
      analyze(fixed, Keyword.put(opts, :source, fixed)).issues
    else
      []
    end
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

  `:priority` is the dispatch order within a round (lower first; 500 is the
  default). It decides which rule wins a diagnostic when two match the same one,
  and reading it here is how you see that cascade without opening the sources.

  `:unsafe_in_dsl` is the macro-DSL families a Pattern rule declares itself unsafe
  inside (Rule Standard item 5) — a list, or `:all` for a rule unsafe in every
  family. It is `nil` for Syntax and Semantic, where the question does not arise.
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
        priority: rule.priority(),
        # `nil`, not `[]`. DSL safety is a Pattern-round question: a Syntax rule
        # only runs on source that does not parse and a Semantic rule only on a
        # compiler diagnostic, so neither can land inside a macro DSL's block.
        # `[]` would claim "declared safe everywhere", which is a different and
        # unearned statement.
        unsafe_in_dsl: nil,
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
