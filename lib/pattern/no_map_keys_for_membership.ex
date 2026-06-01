defmodule Credence.Pattern.NoMapKeysForMembership do
  @moduledoc """
  Detects `x in Map.keys(m)` and `x not in Map.keys(m)` used for membership
  testing, and rewrites to `Map.has_key?(m, x)` / `not Map.has_key?(m, x)`.

  `Map.keys/1` builds an O(n) list just to check membership — `Map.has_key?/2`
  does the same check in O(log n) without allocating a list.

  ## Bad

      Enum.filter(queue, &(&1 not in Map.keys(visited)))
      if x in Map.keys(cache), do: cached, else: compute(x)

  ## Good

      Enum.reject(queue, &Map.has_key?(visited, &1))
      if Map.has_key?(cache, x), do: cached, else: compute(x)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    find_issues(ast)
  end

  @impl true
  def fix_patches(ast, _opts) do
    # The `:in` node's byte range in `x not in Map.keys(m)` includes the
    # `not` keyword, so standard AST-diff patches at the `:in` level would
    # overwrite `not`. We walk manually and emit patches at the outermost
    # covering node, skipping children of already-matched `not in`.
    collect_fix_patches(ast)
  end

  # ── fix helpers (manual walk — patches at outermost covering node) ─

  # x not in Map.keys(m) → not Map.has_key?(m, x)
  # Emit patch at the `{:not, ...}` range and recurse into left + map
  # (but NOT into the inner `{:in, ...}` which is subsumed).
  defp collect_fix_patches({:not, _meta, [{:in, _, [left, {{:., _, [{:__aliases__, _, [:Map]}, :keys]}, _, [map]}]}]} = node) do
    case Sourceror.get_range(node) do
      %Sourceror.Range{} = range ->
        replacement = "not " <> Sourceror.to_string(has_key_call(map, left))
        [%{range: range, change: replacement} | collect_fix_patches(left) ++ collect_fix_patches(map)]

      _ ->
        collect_fix_patches(left) ++ collect_fix_patches(map)
    end
  end

  # x in Map.keys(m) → Map.has_key?(m, x)
  defp collect_fix_patches({:in, _meta, [left, {{:., _, [{:__aliases__, _, [:Map]}, :keys]}, _, [map]}]} = node) do
    case Sourceror.get_range(node) do
      %Sourceror.Range{} = range ->
        replacement = Sourceror.to_string(has_key_call(map, left))
        [%{range: range, change: replacement} | collect_fix_patches(left) ++ collect_fix_patches(map)]

      _ ->
        collect_fix_patches(left) ++ collect_fix_patches(map)
    end
  end

  # Generic tuple — decompose and recurse
  defp collect_fix_patches(node) when is_tuple(node) do
    node |> Tuple.to_list() |> Enum.flat_map(&collect_fix_patches/1)
  end

  defp collect_fix_patches(node) when is_list(node) do
    Enum.flat_map(node, &collect_fix_patches/1)
  end

  defp collect_fix_patches(_), do: []

  # ── check helpers (manual walk to avoid double-counting) ──────────

  # x not in Map.keys(m) — must come before the bare `in` clause
  defp find_issues({:not, meta, [{:in, _, [left, {{:., _, [{:__aliases__, _, [:Map]}, :keys]}, _, [map]}]}]}) do
    [issue(meta) | find_issues(left) ++ find_issues(map)]
  end

  # x in Map.keys(m)
  defp find_issues({:in, meta, [left, {{:., _, [{:__aliases__, _, [:Map]}, :keys]}, _, [map]}]}) do
    [issue(meta) | find_issues(left) ++ find_issues(map)]
  end

  # Generic tuple — decompose and recurse
  defp find_issues(node) when is_tuple(node) do
    node |> Tuple.to_list() |> Enum.flat_map(&find_issues/1)
  end

  defp find_issues(node) when is_list(node) do
    Enum.flat_map(node, &find_issues/1)
  end

  defp find_issues(_), do: []

  # ── AST builders ──────────────────────────────────────────────────

  defp has_key_call(map, key) do
    {{:., [], [{:__aliases__, [], [:Map]}, :has_key?]}, [], [map, key]}
  end

  defp issue(meta) do
    %Issue{
      rule: :no_map_keys_for_membership,
      message:
        "`x in Map.keys(m)` builds an O(n) list just to check membership. " <>
          "Use `Map.has_key?(m, x)` for an O(log n) check without allocation.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
