defmodule Credence.Rule.NoEnumCountForLength do
  @moduledoc """
  Detects `Enum.count/1` (without a predicate) and suggests `length/1`
  or a more specific size function.

  ## Why this matters

  `Enum.count/1` goes through the `Enumerable` protocol, adding dispatch
  overhead.  When the argument is a list — which it almost always is in
  LLM-generated code — `length/1` is a BIF that does the same traversal
  without protocol dispatch:

      # Flagged — protocol dispatch overhead
      total = Enum.count(chars)

      # Idiomatic — BIF, no protocol overhead
      total = length(chars)

  For other collection types, more specific functions exist:
  `map_size/1` for maps, `MapSet.size/1` for sets, `tuple_size/1`
  for tuples.

  ## Flagged patterns

  Only the **single-argument** form `Enum.count(x)` is flagged.
  The two-argument form `Enum.count(x, predicate)` is not flagged
  because it filters and counts in one pass — there is no simpler
  replacement.
  """

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case check_node(node) do
          {:ok, issue} -> {node, [issue | issues]}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      # Direct: Enum.count(expr) → length(expr)
      # Must not match the predicate-only piped form
      {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, [arg]} = node ->
        if predicate?(arg) do
          node
        else
          {:length, [], [arg]}
        end

      # Pipeline: ... |> Enum.count() → ... |> length()
      {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, []} ->
        {:length, [], []}

      node ->
        node
    end)
    |> Sourceror.to_string()
  end

  defp check_node({{:., meta, [mod, :count]}, _, [arg]}) do
    if enum_module?(mod) and not predicate?(arg) do
      {:ok, build_issue(meta)}
    else
      :error
    end
  end

  defp check_node({{:., meta, [mod, :count]}, _, []}) do
    if enum_module?(mod) do
      {:ok, build_issue(meta)}
    else
      :error
    end
  end

  defp check_node(_), do: :error

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?(_), do: false

  defp predicate?({:&, _, _}), do: true
  defp predicate?({:fn, _, _}), do: true
  defp predicate?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :no_enum_count_for_length,
      message: """
      `Enum.count/1` used without a predicate.

      If the argument is a list, use `length/1` — it's a BIF with \
      no protocol dispatch overhead.

      For other collections, prefer the specific size function:
      `map_size/1` for maps, `MapSet.size/1` for sets, `tuple_size/1` \
      for tuples.
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
