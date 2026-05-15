defmodule Credence.Pattern do
  @moduledoc """
  Pattern phase — detects and fixes anti-patterns in Elixir code.

  Delegates to the 80+ rules implementing `Credence.Pattern.Rule` behaviour.
  Rules are discovered automatically and run in priority order (lower first),
  with module name as tiebreaker for determinism.
  """

  require Logger
  alias Credence.RuleHelpers

  @spec analyze(String.t(), keyword()) :: [Credence.Issue.t()]
  def analyze(code_string, opts \\ []) do
    opts = Keyword.put_new(opts, :source, code_string)

    case Code.string_to_quoted(code_string) do
      {:ok, ast} ->
        Enum.flat_map(rules(opts), & &1.check(ast, opts))

      {:error, {line, error_msg, token}} ->
        [parse_error_issue(line, error_msg, token)]
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
          {String.t(), [{module(), non_neg_integer()}]}
  def fix_with_trace(code_string, opts \\ []) do
    all_rules = rules(opts)
    {fixable, _unfixable} = Enum.split_with(all_rules, & &1.fixable?())

    Logger.debug(
      "[credence_fix] starting pattern fix pipeline (#{length(fixable)} fixable rules)"
    )

    if RuleHelpers.compiles?(code_string) do
      run_fixable_rules(fixable, code_string, opts)
    else
      Logger.debug(
        "[credence_fix] source does not compile, skipping pattern fix pipeline"
      )

      {code_string, []}
    end
  end

  defp run_fixable_rules(fixable, code_string, opts) do
    {code, applied} =
      Enum.reduce(fixable, {code_string, []}, fn rule, {source, applied} ->
        name = RuleHelpers.rule_name(rule)

        case Code.string_to_quoted(source) do
          {:ok, ast} ->
            check_opts = Keyword.put(opts, :source, source)
            issues = rule.check(ast, check_opts)

            if issues != [] do
              Logger.debug(
                "[credence_fix] #{name}: check found #{length(issues)} issue(s), running fix..."
              )

              fixed = rule.fix(source, check_opts)

              if fixed == source do
                Logger.debug("[credence_fix] #{name}: fix returned IDENTICAL source (no change)")
              else
                RuleHelpers.log_diff(name, source, fixed)
              end

              {fixed, [{rule, length(issues)} | applied]}
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
      Enum.map_join(applied, ", ", fn {mod, count} ->
        "#{RuleHelpers.rule_name(mod)}(#{count})"
      end)

    Logger.debug("[credence_fix] done. Applied: [#{summary}]")

    {code, applied}
  end

  defp rules(opts) do
    Keyword.get(opts, :rules, default_rules())
  end

  @doc false
  def default_rules do
    RuleHelpers.discover_rules(Credence.Pattern.Rule)
  end

  defp parse_error_issue(line, error_msg, token) do
    %Credence.Issue{
      rule: :parse_error,
      message: "Syntax error: #{error_msg} at token #{inspect(token)}",
      meta: %{line: line}
    }
  end
end
