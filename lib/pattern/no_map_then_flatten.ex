defmodule Credence.Pattern.NoMapThenFlatten do
  @moduledoc """
  Detects `Enum.map/2` piped to or wrapped by `List.flatten/1`.

  When a `map` builds nested lists and immediately flattens them,
  `Enum.flat_map/2` does the same work in a single pass and is the
  idiomatic Elixir idiom.

  ## Bad

      Enum.map(list, fn x -> [x, x + 1] end) |> List.flatten()

      List.flatten(Enum.map(list, fn x -> [x, x + 1] end))

      list
      |> Enum.map(fn x -> [x, x + 1] end)
      |> List.flatten()

  ## Good

      Enum.flat_map(list, fn x -> [x, x + 1] end)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Piped: ... |> List.flatten() where rightmost on left is Enum.map
        {:|>, _,
         [
           left,
           {{:., _, [{:__aliases__, _, [:List]}, :flatten]}, flatten_meta, []}
         ]} = node,
        acc ->
          if remote_call?(rightmost(left), :Enum, :map) do
            {node, [build_issue(flatten_meta) | acc]}
          else
            {node, acc}
          end

        # Nested: List.flatten(Enum.map(...))
        {{:., _, [{:__aliases__, _, [:List]}, :flatten]}, flatten_meta,
         [
           {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, _}
         ]} = node,
        acc ->
          {node, [build_issue(flatten_meta) | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, source: source) do
    Credence.RuleHelpers.patches_from_ast_transform(ast, source, fn ast ->
      transform_ast(ast)
    end)
  end

  defp transform_ast(ast) do
    Macro.postwalk(ast, fn
      # Piped: ... |> List.flatten()
      {:|>, pipe_meta,
       [
         left,
         {{:., _, [{:__aliases__, _, [:List]}, :flatten]}, _, []}
       ]} ->
        map_call = rightmost(left)

        if remote_call?(map_call, :Enum, :map) do
          coll = extract_coll(left, map_call)
          fun = extract_mapper(map_call)
          pre = remove_rightmost_pipe(left, map_call)

          case pre do
            nil -> build_full_flat_map(coll, fun)
            p -> {:|>, pipe_meta, [p, flat_map_1arg(fun)]}
          end
        else
          {:|>, pipe_meta,
           [
             left,
             {{:., [], [{:__aliases__, [], [:List]}, :flatten]}, [], []}
           ]}
        end

      # Nested: List.flatten(Enum.map(coll, f))
      {{:., _, [{:__aliases__, _, [:List]}, :flatten]}, _,
       [
         {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, args} = map_call
       ]} ->
        case args do
          [coll, fun] -> build_full_flat_map(coll, fun)
          _ -> {{:., [], [{:__aliases__, [], [:List]}, :flatten]}, [], [map_call]}
        end

      node ->
        node
    end)
  end

  # Extract the collection from an Enum.map call that is `map_call` within
  # the pipe chain rooted at `left`.
  #
  # 1-arg map (Enum.map in pipe): coll comes from before map in the chain
  # 2-arg map (Enum.map(coll, f)): coll is the first arg of the map call
  defp extract_coll(left, map_call) do
    case map_call do
      {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [coll, _fun]} ->
        coll

      {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [_fun]} ->
        extract_pre_pipe_coll(left, map_call)
    end
  end

  # Walk the pipe chain leftward to find the collection.
  # `left` is the pipe chain before the Enum.map step.
  defp extract_pre_pipe_coll(left, map_call) do
    case left do
      # The map_call IS the direct right of this pipe: coll comes from left's left
      {:|>, _, [inner_left, ^map_call]} ->
        inner_left

      # Another pipe wrapping: keep walking
      {:|>, _, [deeper, _right]} ->
        extract_pre_pipe_coll(deeper, map_call)

      # left itself is the map_call (shouldn't happen for 1-arg, but safe fallback)
      ^map_call ->
        {:__aliases__, [], [:TODO]}
    end
  end

  defp rightmost({:|>, _, [_, right]}), do: right
  defp rightmost(other), do: other

  defp remote_call?(node, mod, func) do
    match?({{:., _, [{:__aliases__, _, [^mod]}, ^func]}, _, _}, node)
  end

  defp extract_mapper({{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, args}) do
    case args do
      [_coll, fun] -> fun
      [fun] -> fun
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

  defp flat_map_1arg(fun) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :flat_map]}, [], [fun]}
  end

  defp build_full_flat_map(coll, fun) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :flat_map]}, [], [coll, fun]}
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_map_then_flatten,
      message:
        "`Enum.map/2` piped to `List.flatten/1` creates an unnecessary " <>
          "intermediate nested list. Use `Enum.flat_map/2` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
