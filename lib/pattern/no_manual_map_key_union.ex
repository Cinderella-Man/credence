defmodule Credence.Pattern.NoManualMapKeyUnion do
  @moduledoc """
  Detects manual key union of two maps built via
  `Map.keys(m1) ++ Map.keys(m2) |> Enum.uniq()` (or the nested form
  `Enum.uniq(Map.keys(m1) ++ Map.keys(m2))`), and rewrites to
  `Map.merge(m1, m2) |> Map.keys()`.

  `Map.merge/2` returns a map with all keys from both inputs (right-biased
  on conflicts), so `Map.keys(Map.merge(m1, m2))` is the same set of unique
  keys — without allocating two intermediate lists and deduplicating.

  ## Bad

      Map.keys(freq1) ++ Map.keys(freq2) |> Enum.uniq()
      Enum.uniq(Map.keys(a) ++ Map.keys(b))

  ## Good

      Map.merge(freq1, freq2) |> Map.keys()
      Map.keys(Map.merge(a, b))
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  # ── check ──────────────────────────────────────────────────────────

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case match_key_union(node) do
          {_m1, _m2} -> {node, [issue(meta_of(node)) | acc]}
          :no -> {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  # ── fix ────────────────────────────────────────────────────────────

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)

    Credence.RuleHelpers.patches_from_ast_transform(ast, source, fn input ->
      Macro.postwalk(input, fn node ->
        case match_key_union(node) do
          {m1, m2} -> build_fix(m1, m2)
          :no -> node
        end
      end)
    end)
  end

  # ── matching ───────────────────────────────────────────────────────

  # Pipe form: Map.keys(m1) ++ Map.keys(m2) |> Enum.uniq()
  defp match_key_union(
         {:|>, _,
          [
            {:++, _,
             [
               {{:., _, [{:__aliases__, _, [:Map]}, :keys]}, _, [m1]},
               {{:., _, [{:__aliases__, _, [:Map]}, :keys]}, _, [m2]}
             ]},
            {{:., _, [{:__aliases__, _, [:Enum]}, :uniq]}, _, []}
          ]}
       ) do
    {m1, m2}
  end

  # Nested form: Enum.uniq(Map.keys(m1) ++ Map.keys(m2))
  defp match_key_union(
         {{:., _, [{:__aliases__, _, [:Enum]}, :uniq]}, _,
          [
            {:++, _,
             [
               {{:., _, [{:__aliases__, _, [:Map]}, :keys]}, _, [m1]},
               {{:., _, [{:__aliases__, _, [:Map]}, :keys]}, _, [m2]}
             ]}
          ]}
       ) do
    {m1, m2}
  end

  defp match_key_union(_), do: :no

  # ── AST builders ───────────────────────────────────────────────────

  defp build_fix(m1, m2) do
    # Map.merge(m1, m2) |> Map.keys()
    merge = {{:., [], [{:__aliases__, [], [:Map]}, :merge]}, [], [m1, m2]}
    keys = {{:., [], [{:__aliases__, [], [:Map]}, :keys]}, [], []}
    {:|>, [], [merge, keys]}
  end

  defp meta_of({:|>, meta, _}), do: meta
  defp meta_of({{:., _, _}, meta, _}), do: meta
  defp meta_of(_), do: []

  defp issue(meta) do
    %Issue{
      rule: :no_manual_map_key_union,
      message:
        "`Map.keys(m1) ++ Map.keys(m2) |> Enum.uniq()` manually builds a key union. " <>
          "Use `Map.merge(m1, m2) |> Map.keys()` for the same result without intermediate lists.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
