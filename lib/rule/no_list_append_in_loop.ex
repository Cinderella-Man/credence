defmodule Credence.Rule.NoListAppendInLoop do
  @moduledoc """
  Performance rule: Detects the use of `++` inside looping constructs
  (`Enum.reduce`, `for` comprehensions) and inside recursive functions.

  Appending to a list with `++` is O(n) because it must copy the entire
  left-hand list. Inside a loop or recursion this compounds to O(n²).
  Prefer prepending with `[item | acc]` and calling `Enum.reverse/1`
  after the loop completes.

  ## Bad — inside Enum.reduce

      Enum.reduce(list, [], fn item, acc ->
        acc ++ [item * 2]
      end)

  ## Bad — inside a recursive function

      defp slide([next | rest], window, current, max) do
        new_window = window ++ [next]
        slide(rest, new_window, current, max)
      end

  ## Good

      Enum.reduce(list, [], fn item, acc ->
        [item * 2 | acc]
      end)
      |> Enum.reverse()
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    # Step 1: Traverse the AST looking for looping constructs
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Match Enum.reduce/3 (the AST representation of a remote call to Enum.reduce)
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [_enumerable, _acc, fun]} = node,
        issues ->
          {node, find_append(fun, issues)}

        # Match 'for' comprehensions
        {:for, _, args} = node, issues when is_list(args) ->
          # The 'do' block is typically the last keyword argument in the comprehension
          do_block = Keyword.get(List.last(args) || [], :do)
          {node, find_append(do_block, issues)}

        # Match def/defp where the body contains both ++ and a recursive call
        {kind, _, [{:when, _, [{name, _, _params}, _guard]}, body_kw]} = node, issues
        when kind in [:def, :defp] and is_atom(name) ->
          body = extract_body(body_kw)
          {node, find_append_in_recursive(body, name, issues)}

        {kind, _, [{name, _, _params}, body_kw]} = node, issues
        when kind in [:def, :defp] and is_atom(name) ->
          body = extract_body(body_kw)
          {node, find_append_in_recursive(body, name, issues)}

        # If it's not a loop, keep walking
        node, issues ->
          {node, issues}
      end)

    # Reverse to keep chronological order (since we prepended to the list)
    Enum.reverse(issues)
  end

  # Step 2: Traverse *only* the body of the loop to find `++`
  defp find_append(ast, acc) do
    {_ast, issues} =
      Macro.prewalk(ast, acc, fn
        # Match the `++` operator
        {:++, meta, _args} = node, issues ->
          {node, [build_issue(meta) | issues]}

        node, issues ->
          {node, issues}
      end)

    issues
  end

  # Step 3: For def/defp bodies, only flag ++ if the function is recursive
  defp find_append_in_recursive(nil, _name, acc), do: acc

  defp find_append_in_recursive(body, name, acc) do
    has_recursive_call = body_calls_self?(body, name)

    if has_recursive_call do
      find_append(body, acc)
    else
      acc
    end
  end

  defp body_calls_self?(body, name) do
    {_ast, found} =
      Macro.prewalk(body, false, fn
        {^name, _, args} = node, _acc when is_list(args) ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp extract_body(body_kw) when is_list(body_kw), do: Keyword.get(body_kw, :do)
  defp extract_body(body), do: body

  defp build_issue(meta) do
    %Issue{
      rule: :no_list_append_in_loop,
      message:
        "Avoid using '++' inside loops or recursive functions. Prefer prepending with '[item | acc]' and calling 'Enum.reverse/1' outside the loop.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
