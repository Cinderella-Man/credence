defmodule Credence.Pattern.NoFetchThenUpdate do
  @moduledoc """
  Detects `Map.update!/3` or `Map.update/4` called inside a
  `case Map.fetch/2` `{:ok, val}` branch on the same map and key.

  `Map.fetch/2` already traversed the map to retrieve `val`. Calling
  `Map.update!` or `Map.update` on the same key performs a second
  traversal. Since `val` is available, use `Map.put/3` with the
  computed value instead.

  Only flags `Map.update!`/`Map.update` calls whose map and key both
  match the outer `Map.fetch`.

  ## Bad

      case Map.fetch(counts, key) do
        {:ok, n} ->
          {n, Map.update!(counts, key, &(&1 + 1))}

        :error ->
          {0, Map.put(counts, key, 1)}
      end

  ## Good

      case Map.fetch(counts, key) do
        {:ok, n} ->
          {n, Map.put(counts, key, n + 1)}

        :error ->
          {0, Map.put(counts, key, 1)}
      end

  ## Auto-fix

  Not implemented — replacing `Map.update!(map, key, fun)` with
  `Map.put(map, key, fun.(val))` requires inlining the function
  application, which is complex for arbitrary captured functions.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        node, acc ->
          case detect_fetch_then_update(node) do
            {:ok, issue} -> {node, [issue | acc]}
            :none -> {node, acc}
          end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # Matches: case Map.fetch(map, key) do ... end
  defp detect_fetch_then_update(
         {:case, _case_meta,
          [
            {{:., _, [{:__aliases__, _, [:Map]}, :fetch]}, _, [fetch_map, fetch_key]},
            [{{:__block__, _, [:do]}, clauses}]
          ]}
       )
       when is_list(clauses) do
    fetch_map_s = Macro.to_string(fetch_map)
    fetch_key_s = Macro.to_string(fetch_key)

    issues =
      Enum.flat_map(clauses, fn
        # Sourceror represents {:ok, val} -> body as:
        # {:->, meta, [{:__block__, _, [{{:__block__, _, [:ok]}, {val, _, nil}}]}, body]}
        {:->, line_meta,
         [
           [{:__block__, _, [{{:__block__, _, [:ok]}, {bound_val, _, nil}}]}],
           body
         ]}
         when is_atom(bound_val) ->
          find_update_calls(body, fetch_map_s, fetch_key_s, bound_val, line_meta)

        _ ->
          []
      end)

    case issues do
      [issue | _] -> {:ok, issue}
      [] -> :none
    end
  end

  defp detect_fetch_then_update(_), do: :none

  # Walks the body of a {:ok, val} branch looking for Map.update!/Map.update
  # calls on the same map and key.
  defp find_update_calls(body, fetch_map_s, fetch_key_s, bound_val, meta) do
    {_body, found} =
      Macro.prewalk(body, [], fn
        {{:., _, [{:__aliases__, _, [:Map]}, update_func]}, call_meta,
         [update_map, update_key | _rest]} = node,
        acc
        when update_func in [:update!, :update] ->
          update_map_s = Macro.to_string(update_map)
          update_key_s = Macro.to_string(update_key)

          if update_map_s == fetch_map_s and update_key_s == fetch_key_s do
            line = Keyword.get(call_meta, :line) || Keyword.get(meta, :line)

            issue = %Issue{
              rule: :no_fetch_then_update,
              message:
                "`Map.update` on `#{update_map_s}` key `#{update_key_s}` inside " <>
                  "`case Map.fetch` branch — the value is already fetched as `#{bound_val}`. " <>
                  "Use `Map.put(#{update_map_s}, #{update_key_s}, ...)` instead.",
              meta: %{line: line}
            }

            {node, [issue | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    found
  end
end
