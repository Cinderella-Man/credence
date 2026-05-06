defmodule Credence.Pattern do
  @moduledoc """
  Pattern phase — detects and fixes anti-patterns in Elixir code.

  Delegates to the 80+ rules implementing `Credence.Pattern.Rule` behaviour.
  Rules are discovered automatically and run in priority order (lower first),
  with module name as tiebreaker for determinism.
  """

  require Logger

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
  """
  @spec fix_with_trace(String.t(), keyword()) ::
          {String.t(), [{module(), non_neg_integer()}]}
  def fix_with_trace(code_string, opts \\ []) do
    all_rules = rules(opts)
    {fixable, _unfixable} = Enum.split_with(all_rules, & &1.fixable?())

    Logger.debug(
      "[credence_fix] starting pattern fix pipeline (#{length(fixable)} fixable rules)"
    )

    {code, applied} =
      Enum.reduce(fixable, {code_string, []}, fn rule, {source, applied} ->
        rule_name = rule |> Module.split() |> List.last()

        case Code.string_to_quoted(source) do
          {:ok, ast} ->
            issues = rule.check(ast, opts)

            if issues != [] do
              Logger.debug(
                "[credence_fix] #{rule_name}: check found #{length(issues)} issue(s), running fix..."
              )

              fixed = rule.fix(source, opts)

              if fixed == source do
                Logger.debug(
                  "[credence_fix] #{rule_name}: fix returned IDENTICAL source (no change)"
                )
              else
                log_diff(rule_name, source, fixed)
              end

              {fixed, [{rule, length(issues)} | applied]}
            else
              {source, applied}
            end

          {:error, reason} ->
            Logger.debug(
              "[credence_fix] source no longer parses at #{rule_name}: #{inspect(reason)}"
            )

            {source, applied}
        end
      end)

    applied = Enum.reverse(applied)

    summary =
      Enum.map_join(applied, ", ", fn {mod, count} ->
        "#{mod |> Module.split() |> List.last()}(#{count})"
      end)

    Logger.debug("[credence_fix] done. Applied: [#{summary}]")

    {code, applied}
  end

  # ── Diff helper ──────────────────────────────────────────────────

  defp log_diff(rule_name, before, after_fix) do
    before_lines = String.split(before, "\n")
    after_lines = String.split(after_fix, "\n")

    changes =
      diff_lines(before_lines, after_lines)
      |> Enum.take(10)

    change_summary =
      Enum.map_join(changes, "\n", fn
        {:removed, line_no, text} -> "  L#{line_no} - #{String.trim(text)}"
        {:added, line_no, text} -> "  L#{line_no} + #{String.trim(text)}"
      end)

    more =
      if length(diff_lines(before_lines, after_lines)) > 10,
        do: "\n  ... (#{length(diff_lines(before_lines, after_lines)) - 10} more changes)",
        else: ""

    Logger.debug("[credence_fix] #{rule_name}: source CHANGED:\n#{change_summary}#{more}")
  end

  defp diff_lines(before_lines, after_lines) do
    max_len = max(length(before_lines), length(after_lines))

    Enum.flat_map(0..(max_len - 1), fn i ->
      b = Enum.at(before_lines, i)
      a = Enum.at(after_lines, i)

      cond do
        b == a -> []
        is_nil(a) -> [{:removed, i + 1, b}]
        is_nil(b) -> [{:added, i + 1, a}]
        true -> [{:removed, i + 1, b}, {:added, i + 1, a}]
      end
    end)
  end

  # ── Rule discovery ───────────────────────────────────────────────

  defp rules(opts) do
    Keyword.get(opts, :rules, default_rules())
  end

  @doc false
  def default_rules do
    Application.spec(:credence, :modules)
    |> Enum.filter(&implements?(&1, Credence.Pattern.Rule))
    |> Enum.sort_by(&{&1.priority(), &1})
  end

  defp implements?(module, behaviour) do
    behaviour in Keyword.get(module.__info__(:attributes), :behaviour, [])
  end

  defp parse_error_issue(line, error_msg, token) do
    %Credence.Issue{
      rule: :parse_error,
      message: "Syntax error: #{error_msg} at token #{inspect(token)}",
      meta: %{line: line}
    }
  end
end
