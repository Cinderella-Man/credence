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

  ## Safety: only side-effect-free left operands

  `x in Map.keys(m)` evaluates the right operand (`Map.keys(m)`) **before** the
  left (`x`), whereas the rewrite `Map.has_key?(m, x)` evaluates `x` before `m`.
  When the left operand has observable side effects this reorders them, so the
  rule fires **only** when the left operand is statically side-effect-free — a
  bare variable or a capture argument (`&1`).
  For those, reordering is unobservable and the rewrite is behaviour-preserving
  (membership via `in`/`Enum.member?` and map-key lookup both use term equality,
  and both raise `BadMapError` on a non-map).
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
  # Recurse into left + map only (NOT generically into the inner `{:in, ...}`,
  # which is subsumed by this patch).
  defp collect_fix_patches({:not, _meta, [{:in, _, [left, {{:., _, [{:__aliases__, _, [:Map]}, :keys]}, _, [map]}]} = in_node]}) do
    # Patch at the inner `:in` node: its range spans the whole `x not in
    # Map.keys(m)` (including `x` and `not`), whereas the `:not` node's range
    # starts at `not` and would leave the left operand `x` dangling.
    with true <- safe_left?(left),
         %Sourceror.Range{} = range <- Sourceror.get_range(in_node) do
      replacement = "not " <> Sourceror.to_string(has_key_call(map, left))
      [%{range: range, change: replacement} | collect_fix_patches(left) ++ collect_fix_patches(map)]
    else
      _ -> collect_fix_patches(left) ++ collect_fix_patches(map)
    end
  end

  # x in Map.keys(m) → Map.has_key?(m, x)
  defp collect_fix_patches({:in, _meta, [left, {{:., _, [{:__aliases__, _, [:Map]}, :keys]}, _, [map]}]} = node) do
    with true <- safe_left?(left),
         %Sourceror.Range{} = range <- Sourceror.get_range(node) do
      replacement = Sourceror.to_string(has_key_call(map, left))
      [%{range: range, change: replacement} | collect_fix_patches(left) ++ collect_fix_patches(map)]
    else
      _ -> collect_fix_patches(left) ++ collect_fix_patches(map)
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
    if safe_left?(left) do
      [issue(meta) | find_issues(left) ++ find_issues(map)]
    else
      find_issues(left) ++ find_issues(map)
    end
  end

  # x in Map.keys(m)
  defp find_issues({:in, meta, [left, {{:., _, [{:__aliases__, _, [:Map]}, :keys]}, _, [map]}]}) do
    if safe_left?(left) do
      [issue(meta) | find_issues(left) ++ find_issues(map)]
    else
      find_issues(left) ++ find_issues(map)
    end
  end

  # Generic tuple — decompose and recurse
  defp find_issues(node) when is_tuple(node) do
    node |> Tuple.to_list() |> Enum.flat_map(&find_issues/1)
  end

  defp find_issues(node) when is_list(node) do
    Enum.flat_map(node, &find_issues/1)
  end

  defp find_issues(_), do: []

  # ── safety guard ──────────────────────────────────────────────────

  # A left operand is safe to reorder only if evaluating it has no observable
  # side effects: a capture argument (`&1`) or a bare variable. Anything else
  # (calls, lists, tuples, blocks, even literals — which Sourceror wraps in
  # `:__block__`) is left untouched, since a side-effecting left operand's
  # evaluation order relative to `Map.keys(m)` would change under the rewrite.
  defp safe_left?({:&, _, [n]}) when is_integer(n), do: true
  defp safe_left?({name, _, ctx}) when is_atom(name) and (is_atom(ctx) or is_nil(ctx)), do: true
  defp safe_left?(_), do: false

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
