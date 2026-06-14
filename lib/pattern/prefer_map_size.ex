defmodule Credence.Pattern.PreferMapSize do
  @moduledoc """
  Detects `Map.keys/1` piped into `Enum.count/1` (or called directly) and
  rewrites to `map_size/1`.

  `Map.keys/1` builds an intermediate list of all keys just to count them.
  `map_size/1` is an O(1) BIF that returns the same `non_neg_integer` without
  allocating the list.

  ## Bad

      Map.keys(courses) |> Enum.count()
      Enum.count(Map.keys(courses))

  ## Good

      map_size(courses)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

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
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      # Pipeline: Map.keys(arg) |> Enum.count() → map_size(arg)
      {:|>, _,
       [
         {{:., _, [{:__aliases__, _, [:Map]}, :keys]}, _, [arg]},
         {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, []}
       ]} ->
        {:map_size, [], [arg]}

      # Direct: Enum.count(Map.keys(arg)) → map_size(arg)
      {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _,
       [{{:., _, [{:__aliases__, _, [:Map]}, :keys]}, _, [arg]}]} ->
        {:map_size, [], [arg]}

      node ->
        node
    end)
  end

  # ── Check helpers ──────────────────────────────────────────────────

  # Pipeline: Map.keys(arg) |> Enum.count()
  defp check_node(
         {:|>, _,
          [
            {{:., _, [{:__aliases__, _, [:Map]}, :keys]}, meta, _args},
            {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, []}
          ]}
       ) do
    {:ok, build_issue(meta)}
  end

  # Direct: Enum.count(Map.keys(arg))
  defp check_node(
         {{:., meta, [{:__aliases__, _, [:Enum]}, :count]}, _,
          [{{:., _, [{:__aliases__, _, [:Map]}, :keys]}, _, _}]}
       ) do
    {:ok, build_issue(meta)}
  end

  defp check_node(_), do: :error

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_map_size,
      message:
        "`Map.keys/1` piped into `Enum.count/1` allocates an intermediate list " <>
          "just to count it. Use `map_size/1`, an O(1) BIF that returns the same value.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
