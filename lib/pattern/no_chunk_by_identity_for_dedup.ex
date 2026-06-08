defmodule Credence.Pattern.NoChunkByIdentityForDedup do
  @moduledoc """
  Detects `Enum.chunk_by(enum, identity_fn)` followed by extracting the
  first element of each chunk, which is a verbose reimplementation of
  `Enum.dedup/1`.

  `Enum.dedup/1` removes consecutive duplicates in a single pass with no
  intermediate list allocation.  The `chunk_by + map(first)` pattern
  allocates a list of sublists just to throw them away.

  ## Bad

      Enum.chunk_by(list, & &1) |> Enum.map(&List.first/1)
      list |> Enum.chunk_by(fn x -> x end) |> Enum.map_join(&List.first/1)

  ## Good

      Enum.dedup(list)
      list |> Enum.dedup() |> Enum.join()

  ## Auto-fix

  Replaces `chunk_by(identity) |> map(&List.first/1)` with `Enum.dedup()`,
  and the `map_join` variant with `Enum.dedup() |> Enum.join()`.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def priority, do: 510

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipeline: ... |> Enum.chunk_by(& &1) |> Enum.map(&List.first/1)
        #   or:     ... |> Enum.chunk_by(& &1) |> Enum.map_join(&List.first/1)
        {:|>, meta, [left, right]} = node, issues ->
          chunk_node = rightmost(left)

          if (first_of_chunk_map?(right) or first_of_chunk_join_map?(right)) and
               identity_chunk_by?(chunk_node) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        # Direct: Enum.map(Enum.chunk_by(list, & &1), &List.first/1)
        {{:., _, [{:__aliases__, _, [:Enum]}, func]}, meta, [chunk_node, first_fn]} = node, issues
        when func in [:map, :map_join] ->
          if identity_chunk_by?(chunk_node) and takes_first?(first_fn) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, fn
      # Pipeline: ... |> Enum.chunk_by(& &1) |> Enum.map/map_join(&List.first/1)
      {:|>, pipe_meta, [left, last_call]} = node ->
        chunk_node = rightmost(left)
        is_map = first_of_chunk_map?(last_call)
        is_map_join = first_of_chunk_join_map?(last_call)

        if (is_map or is_map_join) and identity_chunk_by?(chunk_node) do
          source = remove_rightmost_pipe(left, chunk_node)

          case source do
            nil ->
              enum = extract_enum(chunk_node)

              if is_map_join do
                {:|>, pipe_meta, [build_dedup_call(enum), build_join_call()]}
              else
                build_dedup_call(enum)
              end

            pre ->
              if is_map_join do
                dedup_pipe = {:|>, pipe_meta, [pre, build_dedup_piped()]}
                {:|>, pipe_meta, [dedup_pipe, build_join_call()]}
              else
                {:|>, pipe_meta, [pre, build_dedup_piped()]}
              end
          end
        else
          node
        end

      # Direct: Enum.map_join(Enum.chunk_by(enum, & &1), &List.first/1)
      {{:., _, [{:__aliases__, _, [:Enum]}, :map_join]}, _meta, [chunk_node, first_fn]} = node ->
        if identity_chunk_by?(chunk_node) and takes_first?(first_fn) do
          enum = extract_enum(chunk_node)
          pipe = {:|>, [], [build_dedup_call(enum), build_join_call()]}
          pipe
        else
          node
        end

      # Direct: Enum.map(Enum.chunk_by(enum, & &1), &List.first/1)
      {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _meta, [chunk_node, first_fn]} = node ->
        if identity_chunk_by?(chunk_node) and takes_first?(first_fn) do
          enum = extract_enum(chunk_node)
          build_dedup_call(enum)
        else
          node
        end

      node ->
        node
    end)
  end

  # --- Pattern matchers ---

  defp identity_chunk_by?({{:., _, [{:__aliases__, _, [:Enum]}, :chunk_by]}, _meta, args}) do
    callback =
      case args do
        [_enum, cb] -> cb
        [cb] -> cb
        _ -> nil
      end

    callback != nil and identity_fn?(callback)
  end

  defp identity_chunk_by?(_), do: false

  # & &1
  defp identity_fn?({:&, _, [{:&, _, [1]}]}), do: true
  # &(&1)  — Sourceror wraps the 1 in __block__
  defp identity_fn?({:&, _, [{:&, _, [{:__block__, _, [1]}]}]}), do: true
  # fn x -> x end
  defp identity_fn?({:fn, _, [{:->, _, [[{var, _, ctx}], {var, _, ctx}]}]})
       when is_atom(var) and is_atom(ctx),
       do: true

  defp identity_fn?(_), do: false

  # Detects &List.first/1 — plain arity
  defp takes_first?(
         {:&, _,
          [
            {:/, _,
             [
               {{:., _, [{:__aliases__, _, [:List]}, :first]}, _, []},
               1
             ]}
          ]}
       ),
       do: true

  # Detects &List.first/1 — Sourceror __block__-wrapped arity
  defp takes_first?(
         {:&, _,
          [
            {:/, _,
             [
               {{:., _, [{:__aliases__, _, [:List]}, :first]}, _, []},
               {:__block__, _, [1]}
             ]}
          ]}
       ),
       do: true

  # & hd(&1)
  defp takes_first?({:&, _, [{:hd, _, [{:&, _, [1]}]}]}), do: true

  defp takes_first?(_), do: false

  # Enum.map in piped form with &List.first/1 as the mapper
  defp first_of_chunk_map?({{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [first_fn]}) do
    takes_first?(first_fn)
  end

  # Enum.map in direct form
  defp first_of_chunk_map?({{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [_enum, first_fn]}) do
    takes_first?(first_fn)
  end

  defp first_of_chunk_map?(_), do: false

  # Enum.map_join in piped form
  defp first_of_chunk_join_map?({{:., _, [{:__aliases__, _, [:Enum]}, :map_join]}, _, [first_fn]}) do
    takes_first?(first_fn)
  end

  # Enum.map_join in direct form
  defp first_of_chunk_join_map?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :map_join]}, _, [_enum, first_fn]}
       ) do
    takes_first?(first_fn)
  end

  defp first_of_chunk_join_map?(_), do: false

  # --- AST builders ---

  defp build_dedup_call(enum) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :dedup]}, [], [enum]}
  end

  defp build_dedup_piped do
    {{:., [], [{:__aliases__, [], [:Enum]}, :dedup]}, [], []}
  end

  defp build_join_call do
    {{:., [], [{:__aliases__, [], [:Enum]}, :join]}, [], []}
  end

  defp extract_enum({{:., _, [{:__aliases__, _, [:Enum]}, :chunk_by]}, _, args}) do
    case args do
      [enum, _cb] -> enum
      [_cb] -> nil
    end
  end

  defp extract_enum(_), do: nil

  defp rightmost({:|>, _, [_, right]}), do: right
  defp rightmost(other), do: other

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

  defp build_issue(meta) do
    %Issue{
      rule: :no_chunk_by_identity_for_dedup,
      message:
        "`Enum.chunk_by(enum, & &1)` followed by extracting the first of each " <>
          "chunk is a verbose reimplementation of `Enum.dedup/1`.\n\n" <>
          "Use `Enum.dedup(enum)` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
