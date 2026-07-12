defmodule Credence.Semantic.NoCondVariableAssignmentInInnerBranch do
  @moduledoc """
  Fixes `undefined variable` errors caused by LLMs assigning a variable inside
  both branches of an `if`/`else` block and then referencing it after the block.

  LLMs frequently write Python-style patterns like:

      if x > threshold do
        count = 1
      else
        count = 0
      end

      count

  In Elixir, the assignment is scoped to each branch, so `count` is undefined
  after the block. The fix hoists the assignment before the `if`, making the
  block itself the right-hand side of the assignment:

      count =
        if x > threshold do
          1
        else
          0
        end

      count

  Unlike `NoIfAssignmentAsStatement` (which converts to keyword-style
  `if cond, do: x, else: y`), this rule preserves the block-style `if` form,
  which is better suited for longer or more complex branch expressions.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{severity: :error, message: msg, file: file} = _diagnostic)
      when is_binary(msg) and is_binary(file) do
    case extract_var_name(msg) do
      nil ->
        false

      var_name ->
        case File.read(file) do
          {:ok, source} -> source_has_if_branch_assignment_pattern?(source, var_name)
          _ -> false
        end
    end
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :no_cond_variable_assignment_in_inner_branch,
      message: msg,
      meta: %{line: line(position)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    case extract_var_name(msg) do
      nil ->
        source

      var_name ->
        var_atom = String.to_atom(var_name)

        with {:ok, ast} <- Sourceror.parse_string(source) do
          result =
            Macro.prewalk(ast, fn
              {:if, if_meta, [condition, branches_kw]} = node ->
                case extract_both_branches(branches_kw, var_atom) do
                  {:ok, do_value, else_value} ->
                    build_block_assignment(var_atom, condition, do_value, else_value, if_meta)

                  :error ->
                    node
                end

              node ->
                node
            end)

          if result == ast do
            source
          else
            Sourceror.to_string(result)
          end
        else
          _ -> source
        end
    end
  end

  # Extract the variable name from `undefined variable "name"`
  defp extract_var_name(msg) do
    case Regex.run(~r/undefined variable "(\w+)"/, msg) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp line({l, _col}) when is_integer(l), do: l
  defp line(l) when is_integer(l), do: l
  defp line(_), do: nil

  # Check whether the source has an if/else block where both branches assign
  # the same variable (the pattern this rule fixes).
  defp source_has_if_branch_assignment_pattern?(source, var_name) do
    var_atom = String.to_atom(var_name)

    with {:ok, ast} <- Sourceror.parse_string(source) do
      {_ast, found} =
        Macro.prewalk(ast, false, fn
          {:if, _, [_, branches_kw]} = node, false ->
            case extract_both_branches(branches_kw, var_atom) do
              {:ok, _, _} -> {node, true}
              :error -> {node, false}
            end

          node, acc ->
            {node, acc}
        end)

      found
    else
      _ -> false
    end
  end

  # Given an if's keyword branches, check that both :do and :else contain
  # `var = value` and return {value_do, value_else}.
  defp extract_both_branches(branches_kw, var_atom) do
    with {:ok, do_body} <- extract_kw(branches_kw, :do),
         {:ok, else_body} <- extract_kw(branches_kw, :else),
         {:ok, do_value} <- extract_assignment_value(do_body, var_atom),
         {:ok, else_value} <- extract_assignment_value(else_body, var_atom) do
      {:ok, do_value, else_value}
    else
      _ -> :error
    end
  end

  # Extract a keyword body from a Sourceror keyword list.
  defp extract_kw(kw, key) do
    Enum.find_value(kw, :error, fn
      {{:__block__, _, [^key]}, body} -> {:ok, body}
      _ -> nil
    end)
  end

  # If the body is `var = value`, return `{:ok, value}`.
  defp extract_assignment_value({:=, _, [{var, _, nil}, value]}, var_atom) when var == var_atom do
    {:ok, value}
  end

  defp extract_assignment_value(_, _), do: :error

  # Build the replacement AST: `var = if condition do value1 else value2 end`
  # Preserves block-style (do/end) rather than keyword-style (do:, else:).
  defp build_block_assignment(var_atom, condition, do_value, else_value, if_meta) do
    # Keep metadata that preserves block-style rendering.
    # Drop layout-related keys that Sourceror will recalculate.
    clean_meta = Keyword.drop(if_meta, [:end_of_expression, :closing])

    new_if =
      {:if, clean_meta,
       [
         condition,
         [
           {{:__block__, [], [:do]}, do_value},
           {{:__block__, [], [:else]}, else_value}
         ]
       ]}

    {:=, [],
     [
       {var_atom, [], nil},
       new_if
     ]}
  end
end
