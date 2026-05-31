defmodule Credence.Pattern.PreferRegexMatch do
  @moduledoc """
  Detects `case Regex.run(~r/.../, str) do [_ | _] -> ...; _ -> ... end`
  where only the existence of a match is tested, not the captured groups.

  `Regex.match?/2` returns a boolean directly and is the idiomatic way
  to test whether a regex matches a string.

  ## Bad

      case Regex.run(~r/ab{3,}/, string) do
        [_ | _] -> "Found a match!"
        _ -> "Not matched!"
      end

  ## Good

      if Regex.match?(~r/ab{3,}/, string) do
        "Found a match!"
      else
        "Not matched!"
      end
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:case, meta, [regex_run_call, [{{:__block__, _, [:do]}, clauses}]]} = node, issues
        when is_list(clauses) ->
          if regex_run_call?(regex_run_call) and has_cons_wildcard_clause?(clauses) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # Matches `Regex.run(~r/.../, str)` or `Regex.run(~r/.../, str, opts)`
  defp regex_run_call?({{:., _, [{:__aliases__, _, [:Regex]}, :run]}, _, [_regex | _]}), do: true
  defp regex_run_call?(_), do: false

  # Checks if any clause uses a cons pattern with wildcard head/tail: [_ | _]
  # Sourceror wraps list patterns in {:__block__, _, [[...]]}
  defp has_cons_wildcard_clause?(clauses) do
    Enum.any?(clauses, fn
      {:->, _, [[{:__block__, _, [[{:|, _, [{:_, _, _}, {:_, _, _}]}]]}], _body]} -> true
      _ -> false
    end)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_regex_match,
      message:
        "`Regex.run/2` is used only to test whether the regex matches, but `Regex.match?/2` " <>
          "returns a boolean directly and is the idiomatic way to check for a match.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
