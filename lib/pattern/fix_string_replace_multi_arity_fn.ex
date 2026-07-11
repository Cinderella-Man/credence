defmodule Credence.Pattern.FixStringReplaceMultiArityFn do
  @moduledoc """
  Detects `String.replace/4` calls where the replacement is an arity-2
  anonymous function and the trailing options argument is `[]`.

  `String.replace/4` only accepts arity-1 functions or strings as its
  replacement argument.  Passing an arity-2 function compiles but always
  crashes at runtime.  Removing the empty `[]` options switches the call
  to `String.replace/3`, which supports multi-arity callbacks.

  ## Bad

      String.replace(str, ~r/\\d/, fn match, acc -> {"*", acc} end, [])

  ## Good

      String.replace(str, ~r/\\d/, fn match, acc -> {"*", acc} end)
  """
  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:String]}, :replace]}, meta, args} = node, acc
        when length(args) == 4 ->
          case args do
            [_, _, {:fn, _, _} = fn_node, empty_list] ->
              if empty_list_literal?(empty_list) and fn_arity2?(fn_node) do
                {node, [build_issue(meta) | acc]}
              else
                {node, acc}
              end

            _ ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, fn
      {{:., _, [{:__aliases__, _, [:String]}, :replace]}, _, args} = node
      when length(args) == 4 ->
        case args do
          [a1, a2, {:fn, _, _} = fn_node, empty_list] ->
            if empty_list_literal?(empty_list) and fn_arity2?(fn_node) do
              {{:., [], [{:__aliases__, [], [:String]}, :replace]}, [], [a1, a2, fn_node]}
            else
              node
            end

          _ ->
            node
        end

      node ->
        node
    end)
  end

  defp empty_list_literal?({:__block__, _, [[]]}), do: true
  defp empty_list_literal?(_), do: false

  defp fn_arity2?({:fn, _, clauses}) do
    Enum.any?(clauses, fn
      {:->, _, [params, _]} when length(params) >= 2 -> true
      _ -> false
    end)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :fix_string_replace_multi_arity_fn,
      message:
        "`String.replace/4` only accepts arity-1 functions or strings as replacement. " <>
          "An arity-2 callback compiles but crashes at runtime. " <>
          "Remove the trailing `[]` to switch to `String.replace/3`, " <>
          "which supports multi-arity callbacks.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
