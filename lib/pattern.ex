defmodule Credence.Pattern do
  @moduledoc """
  Pattern phase — detects and fixes anti-patterns in Elixir code.

  Delegates to the 117 rules implementing `Credence.Pattern.Rule` behaviour.
  Rules are discovered automatically and run in priority order (lower first),
  with module name as tiebreaker for determinism.
  """

  require Logger
  alias Credence.RuleHelpers

  @spec analyze(String.t(), keyword()) :: [Credence.Issue.t()]
  def analyze(code_string, opts \\ []) do
    opts = Keyword.put_new(opts, :source, code_string)

    case Sourceror.parse_string(code_string) do
      {:ok, ast} ->
        Enum.flat_map(rules(opts), & &1.check(ast, opts))

      {:error, {meta, error_msg, token}} ->
        [parse_error_issue(Keyword.get(meta, :line), error_msg, token)]
    end
  end

  @spec fix(String.t(), keyword()) :: String.t()
  def fix(code_string, opts \\ []) do
    {code, _applied} = fix_with_trace(code_string, opts)
    code
  end

  @doc """
  Like `fix/2`, but also returns a list of `{rule_module, issue_count}` tuples
  for every rule that actually fired and was applied.

  Every step is logged via `Logger.debug` with `[credence_fix]` prefix:
  rule name, issue count, whether the source changed, and a before/after
  diff of the lines that were modified.

  Pattern rules operate on AST and assume semantically valid code.
  If the source does not compile, the pipeline is skipped entirely —
  applying AST transforms to code with undefined variables or functions
  risks introducing new errors and wasting an LLM retry attempt.
  """
  @spec fix_with_trace(String.t(), keyword()) ::
          {String.t(), [{module(), non_neg_integer() | :reverted}]}
  def fix_with_trace(code_string, opts \\ []) do
    all_rules = rules(opts)

    Logger.debug("[credence_fix] starting pattern fix pipeline (#{length(all_rules)} rules)")

    if RuleHelpers.compiles?(code_string) do
      run_fixable_rules(all_rules, code_string, opts)
    else
      Logger.debug("[credence_fix] source does not compile, skipping pattern fix pipeline")

      {code_string, []}
    end
  end

  defp run_fixable_rules(fixable, code_string, opts) do
    {code, applied} =
      Enum.reduce(fixable, {code_string, []}, fn rule, {source, applied} ->
        name = RuleHelpers.rule_name(rule)

        case Sourceror.parse_string(source) do
          {:ok, ast} ->
            check_opts = Keyword.put(opts, :source, source)
            issues = rule.check(ast, check_opts)

            if issues != [] do
              Logger.debug(
                "[credence_fix] #{name}: check found #{length(issues)} issue(s), running fix..."
              )

              fixed = invoke_fix(rule, source, check_opts)
              apply_or_revert(rule, name, source, fixed, issues, applied)
            else
              {source, applied}
            end

          {:error, reason} ->
            Logger.debug("[credence_fix] source no longer parses at #{name}: #{inspect(reason)}")

            {source, applied}
        end
      end)

    applied = Enum.reverse(applied)

    summary =
      Enum.map_join(applied, ", ", fn {mod, count_or_status} ->
        "#{RuleHelpers.rule_name(mod)}(#{count_or_status})"
      end)

    Logger.debug("[credence_fix] done. Applied: [#{summary}]")

    {code, applied}
  end

  # Apply the rule's `fix_patches/2` to the source. See
  # `Credence.RuleHelpers.apply_rule_fix/3`.
  defp invoke_fix(rule, source, opts), do: RuleHelpers.apply_rule_fix(rule, source, opts)

  # Compile-output gate. A rule whose `fix/2` returns source that no
  # longer compiles would otherwise:
  #   - get propagated to the next rule (which then either crashes on
  #     parse or compounds the damage), or
  #   - be returned silently to the caller as a "successful" fix.
  # Instead we revert to the pre-fix source for that rule and mark
  # it as `:reverted` in the trace so the offending rule is visible.
  defp apply_or_revert(rule, name, source, fixed, issues, applied) do
    cond do
      fixed == source ->
        Logger.debug("[credence_fix] #{name}: fix returned IDENTICAL source (no change)")
        {source, applied}

      not RuleHelpers.compiles?(fixed) ->
        Logger.warning("[credence_fix] #{name}: fix produced non-compiling output, reverting")
        # Visibility (Tunex `08` T1.3): log the broken before/after so a reverted
        # fix's diff lands in the row log for the deterministic bugfix-lane seed.
        # The revert *logic* is unchanged — `:reverted` is already a clean signal.
        RuleHelpers.log_diff(name, source, fixed)

        {source, [{rule, :reverted} | applied]}

      true ->
        RuleHelpers.log_diff(name, source, fixed)
        {fixed, [{rule, length(issues)} | applied]}
    end
  end

  # The base list always runs through the assumption filter — even when the
  # caller hands an explicit `rules:` list — so naming a rule can never punch
  # through the safety guarantee. `explicit?` lets the filter warn (not crash)
  # when a rule the caller named by hand gets filtered out.
  defp rules(opts) do
    {base, explicit?} =
      case Keyword.fetch(opts, :rules) do
        {:ok, list} -> {list, true}
        :error -> {default_rules(), false}
      end

    RuleHelpers.filter_by_assumptions(base, opts, explicit?)
  end

  @doc false
  def default_rules do
    RuleHelpers.discover_rules(Credence.Pattern.Rule)
  end

  @doc """
  Returns the status of every rule Credence found (or every rule in an explicit
  `rules:` list), as maps with:

  - `:rule` — the rule module
  - `:name` — its short name
  - `:assumptions` — the promises it needs
  - `:enabled` — whether all of them are on under `opts` right now
  - `:missing` — which needed promises are off

  Honours the same `assumptions:` / `config :credence` settings as `fix/2`, so
  this is the place to answer "what did I promise, and why didn't this rule fire?"
  """
  @spec rule_status(keyword()) :: [
          %{
            rule: module(),
            name: String.t(),
            assumptions: [atom()],
            enabled: boolean(),
            missing: [atom()]
          }
        ]
  def rule_status(opts \\ []) do
    effective = RuleHelpers.effective_assumptions(opts)
    base = Keyword.get(opts, :rules, default_rules())

    Enum.map(base, fn rule ->
      missing = RuleHelpers.missing_assumptions(rule, effective)

      %{
        rule: rule,
        name: RuleHelpers.rule_name(rule),
        assumptions: rule.assumptions(),
        enabled: missing == [],
        missing: missing
      }
    end)
  end

  @doc """
  The short names of the rules that are on under `opts`. Derived from
  `rule_status/1` so the two answers never disagree.
  """
  @spec enabled_rules(keyword()) :: [String.t()]
  def enabled_rules(opts \\ []) do
    opts |> rule_status() |> Enum.filter(& &1.enabled) |> Enum.map(& &1.name)
  end

  defp parse_error_issue(line, error_msg, token) do
    %Credence.Issue{
      rule: :parse_error,
      message: "Syntax error: #{error_msg} at token #{inspect(token)}",
      meta: %{line: line}
    }
  end
end
