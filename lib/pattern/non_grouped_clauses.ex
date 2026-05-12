defmodule Credence.Pattern.NonGroupedClauses do
  @moduledoc """
  Fixes function clauses that are not grouped together.

  When the same function (name + arity) is defined in multiple places in a
  module with other functions between them, the compiler emits a warning
  (which fails compilation under warnings-as-errors).

  ## Bad

      def foo(1), do: 1
      def bar(x), do: x
      def foo(x), do: x + 1   # not grouped with first foo/1!

  ## Good

      def foo(1), do: 1
      def foo(x), do: x + 1
      def bar(x), do: x
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _, [_, [do: {:__block__, _, body}]]} = node, issues ->
          {node, issues ++ check_body(body)}

        node, issues ->
          {node, issues}
      end)

    issues
  end

  @impl true
  def fix(source, _opts) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        fixed = Macro.postwalk(ast, &fix_module_node/1)
        Sourceror.to_string(fixed)

      {:error, _} ->
        source
    end
  end

  # ── Check helpers ───────────────────────────────────────────────

  defp check_body(body) do
    {_, _, _, issues} =
      Enum.reduce(body, {nil, MapSet.new(), MapSet.new(), []}, fn expr,
                                                                  {prev_key, seen, flagged,
                                                                   issues} ->
        case function_key(expr) do
          nil ->
            {nil, seen, flagged, issues}

          key when key == prev_key ->
            {key, seen, flagged, issues}

          key ->
            if key in seen and key not in flagged do
              {name, arity} = key
              meta = elem(expr, 1)

              issue = %Issue{
                rule: :non_grouped_clauses,
                message:
                  "Clauses of `#{name}/#{arity}` are not grouped together. " <>
                    "Move all clauses to be consecutive.",
                meta: %{line: Keyword.get(meta, :line)}
              }

              {key, seen, MapSet.put(flagged, key), [issue | issues]}
            else
              {key, MapSet.put(seen, key), flagged, issues}
            end
        end
      end)

    Enum.reverse(issues)
  end

  # ── Fix helpers ─────────────────────────────────────────────────

  defp fix_module_node({:defmodule, meta, [alias_node, [do: {:__block__, block_meta, body}]]}) do
    new_body = group_clauses(body)
    {:defmodule, meta, [alias_node, [do: {:__block__, block_meta, new_body}]]}
  end

  defp fix_module_node(
         {:defmodule, meta, [alias_node, [{do_tag, {:__block__, block_meta, body}}]]}
       ) do
    new_body = group_clauses(body)
    {:defmodule, meta, [alias_node, [{do_tag, {:__block__, block_meta, new_body}}]]}
  end

  defp fix_module_node(node), do: node

  defp group_clauses(body) do
    indexed = Enum.with_index(body)

    # Phase 1: find stray clause indices
    {_, _, stray_set} =
      Enum.reduce(indexed, {nil, MapSet.new(), MapSet.new()}, fn {expr, idx},
                                                                 {prev_key, seen, strays} ->
        case function_key(expr) do
          nil ->
            {nil, seen, strays}

          key when key == prev_key ->
            {key, seen, strays}

          key ->
            if key in seen do
              {key, seen, MapSet.put(strays, idx)}
            else
              {key, MapSet.put(seen, key), strays}
            end
        end
      end)

    # Don't move clauses preceded by a module attribute (`@impl true`, `@doc`,
    # etc.) — the attribute would be orphaned. `check/2` still flags them.
    stray_set =
      stray_set
      |> Enum.reject(&preceded_by_attr?(body, &1))
      |> MapSet.new()

    if MapSet.size(stray_set) == 0 do
      body
    else
      # Phase 2: remove strays, grouped by function key
      strays_by_key =
        indexed
        |> Enum.filter(fn {_, idx} -> idx in stray_set end)
        |> Enum.group_by(fn {expr, _} -> function_key(expr) end, fn {expr, _} -> expr end)

      cleaned =
        indexed
        |> Enum.reject(fn {_, idx} -> idx in stray_set end)
        |> Enum.map(fn {expr, _} -> expr end)

      # Phase 3: insert each group of strays after the last existing sibling
      Enum.reduce(strays_by_key, cleaned, fn {key, clauses}, acc ->
        insert_after_last_sibling(acc, key, clauses)
      end)
    end
  end

  defp insert_after_last_sibling(body, key, clauses) do
    last_idx =
      body
      |> Enum.with_index()
      |> Enum.filter(fn {expr, _} -> function_key(expr) == key end)
      |> List.last()
      |> elem(1)

    {before, after_part} = Enum.split(body, last_idx + 1)
    before ++ clauses ++ after_part
  end

  # ── Shared helpers ──────────────────────────────────────────────

  defp function_key({kind, _, [{:when, _, [{name, _, args} | _]} | _]})
       when kind in [:def, :defp] and is_atom(name) do
    arity = if is_list(args), do: length(args), else: 0
    {name, arity}
  end

  defp function_key({kind, _, [{name, _, args} | _]})
       when kind in [:def, :defp] and is_atom(name) do
    arity = if is_list(args), do: length(args), else: 0
    {name, arity}
  end

  defp function_key(_), do: nil

  defp preceded_by_attr?(body, idx) do
    idx > 0 and match?({:@, _, _}, Enum.at(body, idx - 1))
  end
end
