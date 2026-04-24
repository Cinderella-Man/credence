defmodule Credence.Rule.NoListAppendInLoop do
  @moduledoc """
  Performance rule: Detects the use of `++` inside `Enum.reduce` or `for` comprehensions.
  Unlike basic linters, this uses AST traversal to isolate the block *inside* the loop.
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
          issue = %Issue{
            rule: :no_list_append_in_loop,
            severity: :high,
            message:
              "Avoid using '++' inside loops. Prefer prepending with '[item | acc]' and calling 'Enum.reverse/1' outside the loop.",
            meta: %{line: Keyword.get(meta, :line)}
          }

          {node, [issue | issues]}

        node, issues ->
          {node, issues}
      end)

    issues
  end
end
