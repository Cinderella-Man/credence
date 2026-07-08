defmodule Credence.Syntax.NoPipeIntoArithmeticOperator do
  @moduledoc """
  Fixes the recurring LLM error of piping into an infix arithmetic operator
  (`/`, `+`, `-`, `*`), which fails at macro expansion with:

      cannot pipe x into foo() / bar(), the :/ operator can only take two arguments

  The pipe operator `|>` has higher precedence than arithmetic operators, so
  `x |> foo() / bar()` parses as `x |> (foo() / bar())` — piping into an
  arithmetic expression rather than into `foo()`. The Elixir pipe macro rejects
  this because the RHS is not a function call.

  The fix extracts the piped value and inserts it as the first argument to the
  function call that is the left operand of the arithmetic:

      # Before (won't compile)
      list |> Enum.sum() / length(list)

      # After (compiles)
      Enum.sum(list) / length(list)
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  @arith_ops [:+, :-, :*, :/]

  @impl true
  def analyze(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {_ast, issues} =
          Macro.prewalk(ast, [], fn
            {:|>, _, [_, {op, op_meta, [call, _right]}]} = node, acc
            when op in @arith_ops and is_tuple(call) and is_list(elem(call, 2)) ->
              line = Keyword.get(op_meta, :line, 0)

              issue = %Issue{
                rule: :no_pipe_into_arithmetic_operator,
                message:
                  "Cannot pipe into arithmetic operator #{op}. " <>
                    "Pass the piped value as an argument to the function instead.",
                meta: %{line: line}
              }

              {node, [issue | acc]}

            node, acc ->
              {node, acc}
          end)

        Enum.reverse(issues)

      {:error, _} ->
        []
    end
  end

  @impl true
  def fix(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {_new_ast, patches} =
          Macro.postwalk(ast, [], fn
            {:|>, _, [piped_value, {op, op_meta, [call, right]}]} = node, acc
            when op in @arith_ops and is_tuple(call) and is_list(elem(call, 2)) ->
              {call_form, call_meta, call_args} = call
              new_call = {call_form, call_meta, [piped_value | call_args]}
              new_node = {op, op_meta, [new_call, right]}
              range = Sourceror.get_range(node)
              replacement = Sourceror.to_string(new_node)
              patch = %{range: range, change: replacement}
              {new_node, [patch | acc]}

            node, acc ->
              {node, acc}
          end)

        case patches do
          [] -> source
          _ -> Sourceror.patch_string(source, patches)
        end

      {:error, _} ->
        source
    end
  end
end
