defmodule Credence.Rule.UseMapJoin do
  @moduledoc """
  Detects `Enum.map/2` chained into `Enum.join/1` or `Enum.join/2`,
  and suggests `Enum.map_join/3` instead.

  ## Why this matters

  `Enum.map/2` followed by `Enum.join` creates a throwaway intermediate
  list.  `Enum.map_join/3` maps and joins in a single pass with no
  intermediate allocation:

  ## Bad

      list
      |> Enum.map(&to_string/1)
      |> Enum.join(", ")

      Enum.join(Enum.map(list, &to_string/1), ", ")

  ## Good

      Enum.map_join(list, ", ", &to_string/1)

      list
      |> Enum.map_join(", ", &to_string/1)

  ## Flagged patterns

  - `Enum.map(enum, f) |> Enum.join()` (pipeline, any separator)
  - `Enum.join(Enum.map(enum, f))` (nested call)
  - Longer pipelines where map and join are adjacent steps

  Only **adjacent** map→join is flagged.  Intervening steps like
  `Enum.map(f) |> Enum.filter(g) |> Enum.join()` are left alone.
  """
  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:|>, meta, [left, right]} = node, issues ->
          if remote_call?(right, :Enum, :join) and
               remote_call?(rightmost(left), :Enum, :map) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, meta,
         [{{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, _} | _rest]} = node,
        issues ->
          {node, [build_issue(meta) | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      # Pipeline: ... |> Enum.map(f) |> Enum.join(sep)
      {:|>, _meta, [left, join_call]} = node ->
        with true <- remote_call?(join_call, :Enum, :join),
             map_call = rightmost(left),
             true <- remote_call?(map_call, :Enum, :map) do
          mapper = extract_mapper(map_call)
          sep = extract_join_sep(join_call)
          pre_map = remove_rightmost_pipe(left, map_call)

          case pre_map do
            nil ->
              # Enum.map(enum, f) |> Enum.join(sep) → Enum.map_join(enum, sep, f)
              case extract_enum(map_call) do
                nil -> node
                enum -> build_full_map_join(enum, sep, mapper)
              end

            pre ->
              # pre |> Enum.map(f) |> Enum.join(sep) → pre |> Enum.map_join(sep, f)
              {:|>, [], [pre, build_map_join_call(sep, mapper)]}
          end
        else
          _ -> node
        end

      # Nested: Enum.join(Enum.map(enum, f), sep)
      {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _meta, join_args} = node ->
        case join_args do
          [map_call | rest] ->
            if remote_call?(map_call, :Enum, :map) do
              case extract_enum(map_call) do
                nil ->
                  node

                enum ->
                  mapper = extract_mapper(map_call)
                  sep = if rest == [], do: nil, else: hd(rest)
                  build_full_map_join(enum, sep, mapper)
              end
            else
              node
            end

          _ ->
            node
        end

      node ->
        node
    end)
    |> Sourceror.to_string()
  end

  # -- Shared helpers --

  defp rightmost({:|>, _, [_, right]}), do: right
  defp rightmost(other), do: other

  defp remote_call?(node, mod, func) do
    match?({{:., _, [{:__aliases__, _, [^mod]}, ^func]}, _, _}, node)
  end

  # -- Fix helpers --

  # Extract the mapper function from an Enum.map call.
  # Handles both 2-arg (direct) and 1-arg (pipeline) forms.
  defp extract_mapper({{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, args}) do
    case args do
      [_enum, mapper] -> mapper
      [mapper] -> mapper
    end
  end

  # Extract the enumerable from a 2-arg Enum.map call.
  # Returns nil for 1-arg calls (pipeline context, enum comes from pipe).
  defp extract_enum({{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, args}) do
    case args do
      [enum, _mapper] -> enum
      [_mapper] -> nil
    end
  end

  # Extract separator from an Enum.join call (in pipeline context, 0–1 args).
  defp extract_join_sep({{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, args}) do
    case args do
      [] -> nil
      [sep] -> sep
    end
  end

  # Remove the rightmost pipe step if it matches `target`.
  # Returns the preceding pipeline, or nil if `left` IS the target.
  defp remove_rightmost_pipe({:|>, meta, [left, right]}, target) do
    if right == target do
      left
    else
      {:|>, meta, [remove_rightmost_pipe(left, target), right]}
    end
  end

  defp remove_rightmost_pipe(node, target) do
    if node == target, do: nil, else: node
  end

  # Build Enum.map_join call in pipeline context (no explicit enum arg).
  defp build_map_join_call(nil, mapper) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :map_join]}, [], [mapper]}
  end

  defp build_map_join_call(sep, mapper) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :map_join]}, [], [sep, mapper]}
  end

  # Build Enum.map_join call in direct context (with explicit enum arg).
  defp build_full_map_join(enum, nil, mapper) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :map_join]}, [], [enum, mapper]}
  end

  defp build_full_map_join(enum, sep, mapper) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :map_join]}, [], [enum, sep, mapper]}
  end

  defp build_issue(meta) do
    %Issue{
      rule: :use_map_join,
      message: """
      `Enum.map/2` piped into `Enum.join` creates an intermediate list.
      Use `Enum.map_join/3` for a single-pass operation:
          Enum.map_join(enumerable, separator, mapper_fn)
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
