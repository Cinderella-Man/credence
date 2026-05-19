defmodule Credence.Pattern.NoListDeleteAtInLoop do
  @moduledoc """
  Performance rule: Detects `List.delete_at/2` inside looping constructs
  (`for`, `Enum.reduce`, `Enum.map`, `Enum.flat_map`) or recursive functions.

  `List.delete_at/2` is O(n) because it must traverse the linked list to the
  given index. Inside a loop this compounds to O(n²) per iteration.

  ## Bad

      for {elem, idx} <- Enum.with_index(list) do
        rest = List.delete_at(list, idx)
        [elem | permutations(rest)]
      end

  ## Good

      # Use List.delete/2 or pass remaining elements via pattern matching
      defp permutations([]), do: [[]]
      defp permutations(list) do
        for elem <- list do
          rest = List.delete(list, elem)
          for perm <- permutations(rest), do: [elem | perm]
        end |> List.flatten()
      end
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @enum_loops [:reduce, :map, :flat_map, :each, :filter]

  @impl true
  def check(ast, _opts) do
    loop_issues = find_in_loops(ast)
    recursive_issues = find_in_recursive(ast)

    # Deduplicate by line — a List.delete_at inside a for inside a recursive
    # function should only be reported once.
    (loop_issues ++ recursive_issues)
    |> Enum.uniq_by(fn issue -> issue.meta.line end)
  end

  # Pass 1: Find List.delete_at inside for/Enum loop constructs
  defp find_in_loops(ast) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:for, _meta, _args} = node, issues ->
          {node, find_delete_at(node, issues)}

        {{:., _, [{:__aliases__, _, [:Enum]}, func]}, _meta, args} = node, issues
        when func in @enum_loops and is_list(args) ->
          {node, find_delete_at(node, issues)}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  # Pass 2: Find List.delete_at in recursive function bodies
  defp find_in_recursive(ast) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {kind, _meta, [{:when, _, [{name, _, _params}, _guard]}, body_kw]} = node, issues
        when kind in [:def, :defp] and is_atom(name) ->
          body = extract_body(body_kw)
          {node, check_recursive_body(body, name, issues)}

        {kind, _meta, [{name, _, _params}, body_kw]} = node, issues
        when kind in [:def, :defp] and is_atom(name) ->
          body = extract_body(body_kw)
          {node, check_recursive_body(body, name, issues)}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp check_recursive_body(nil, _name, acc), do: acc

  defp check_recursive_body(body, name, acc) do
    if body_calls_self?(body, name) do
      find_delete_at(body, acc)
    else
      acc
    end
  end

  defp body_calls_self?(body, name) do
    {_ast, found} =
      Macro.prewalk(body, false, fn
        {^name, _, args} = n, _acc when is_list(args) -> {n, true}
        n, a -> {n, a}
      end)

    found
  end

  defp find_delete_at(scope_ast, acc) do
    {_ast, issues} =
      Macro.prewalk(scope_ast, acc, fn
        {{:., _, [{:__aliases__, _, [:List]}, :delete_at]}, meta, _} = node, issues ->
          issue = %Issue{
            rule: :no_list_delete_at_in_loop,
            message:
              "Avoid `List.delete_at/2` inside loops — it traverses the list to the index (O(n)), " <>
                "creating O(n²) cost per iteration. Use pattern matching or `List.delete/2` instead.",
            meta: %{line: Keyword.get(meta, :line)}
          }

          {node, [issue | issues]}

        node, issues ->
          {node, issues}
      end)

    issues
  end

  defp extract_body(body_kw) when is_list(body_kw), do: Keyword.get(body_kw, :do)
  defp extract_body(body), do: body
end
