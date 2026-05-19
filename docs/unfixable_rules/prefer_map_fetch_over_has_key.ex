defmodule Credence.Pattern.PreferMapFetchOverHasKey do
  @moduledoc """
  Detects `Map.has_key?/2` used in `if`/`cond` conditions, which typically
  leads to a double map lookup — once to check existence, again to get
  the value.

  This is a Python idiom (`if key in dict: val = dict[key]`) that LLMs
  carry over. In Elixir, `Map.fetch/2` or `Map.get/3` combines the
  check and retrieval in a single lookup.

  ## Bad

      if Map.has_key?(map, key) do
        map[key] + 1
      else
        0
      end

      if Map.has_key?(seen, char) and seen[char] >= start do
        seen[char] + 1
      else
        start
      end

  ## Good

      case Map.fetch(map, key) do
        {:ok, value} -> value + 1
        :error -> 0
      end

      case Map.get(seen, char) do
        idx when is_integer(idx) and idx >= start -> idx + 1
        _ -> start
      end

  ## Auto-fix

  Not auto-fixable — the replacement depends on how the value is used
  in the body (simple access, comparison, transformation).
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: false

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:if, meta, [condition | _]} = node, acc ->
          if condition_has_map_has_key?(condition) do
            {node, [build_issue(meta) | acc]}
          else
            {node, acc}
          end

        {:cond, meta, [[do: clauses]]} = node, acc when is_list(clauses) ->
          if Enum.any?(clauses, &clause_has_map_has_key?/1) do
            {node, [build_issue(meta) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  # Check if a condition expression contains Map.has_key?/2
  defp condition_has_map_has_key?({{:., _, [{:__aliases__, _, [:Map]}, :has_key?]}, _, _}),
    do: true

  defp condition_has_map_has_key?({:and, _, [left, right]}),
    do: condition_has_map_has_key?(left) or condition_has_map_has_key?(right)

  defp condition_has_map_has_key?({:or, _, [left, right]}),
    do: condition_has_map_has_key?(left) or condition_has_map_has_key?(right)

  defp condition_has_map_has_key?({:not, _, [expr]}),
    do: condition_has_map_has_key?(expr)

  defp condition_has_map_has_key?(_), do: false

  # Check cond clause: {:->, _, [[condition], _body]}
  defp clause_has_map_has_key?({:->, _, [[condition], _body]}),
    do: condition_has_map_has_key?(condition)

  defp clause_has_map_has_key?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_map_fetch_over_has_key,
      message: """
      `Map.has_key?/2` in a condition typically leads to a double lookup — \
      once to check, again to access the value.

      Use `Map.fetch/2` or `Map.get/3` to combine both in a single lookup:

          case Map.fetch(map, key) do
            {:ok, value} -> use(value)
            :error -> default
          end
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
