defmodule Credence.Semantic.FixCondBranchAssignmentScope do
  @moduledoc """
  Fixes `undefined variable` errors caused by LLMs assigning a variable inside
  a `cond`/`case`/`if` branch and then referencing it after the block.

  In Elixir, variables assigned inside a `cond`/`case`/`if` branch are scoped
  to that branch — they do not leak out. LLMs (familiar with Python/JS) write:

      wma1_val =
        cond do
          true -> Enum.sum(values)
          false -> 0
        end

      wma1_val * 2

  The compiler emits `undefined variable "wma1_val"` because `wma1_val` is only
  defined inside each branch, not after the block.

  The fix moves the post-block usage into each branch, making the block itself
  the final expression:

      cond do
        true -> Enum.sum(values) * 2
        false -> 0 * 2
      end

  This preserves semantics: each branch now returns the value with the operation
  applied, and the block is the function's return value.
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
          {:ok, source} -> source_has_cond_assignment_pattern?(source, var_name)
          _ -> false
        end
    end
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :fix_cond_branch_assignment_scope,
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
          {new_ast, changed} =
            Macro.prewalk(ast, false, fn
              {:__block__, meta, stmts} = node, false when is_list(stmts) ->
                case find_assignment_and_continuation(stmts, var_atom) do
                  {:ok, before_stmts, assign_meta, block, continuation, after_stmts} ->
                    new_block = propagate_continuation(block, var_atom, continuation)
                    new_assignment = {:=, assign_meta, [{var_atom, [], nil}, new_block]}
                    new_stmts = before_stmts ++ [new_assignment] ++ after_stmts
                    {{:__block__, meta, new_stmts}, true}

                  :error ->
                    {node, false}
                end

              node, acc ->
                {node, acc}
            end)

          if changed, do: Sourceror.to_string(new_ast), else: source
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

  # Check if the source has a pattern: var = cond/case/if do ... end
  defp source_has_cond_assignment_pattern?(source, var_name) do
    var_atom = String.to_atom(var_name)

    with {:ok, ast} <- Sourceror.parse_string(source) do
      {_ast, found} =
        Macro.prewalk(ast, false, fn
          {:__block__, _, stmts} = node, false when is_list(stmts) ->
            case find_assignment_and_continuation(stmts, var_atom) do
              {:ok, _, _, _, _, _} -> {node, true}
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

  # In a list of statements, find `var = cond/case/if do ... end` followed by
  # an expression that uses `var`. Returns the pieces needed for the rewrite.
  defp find_assignment_and_continuation(stmts, var_atom) do
    case Enum.find_index(stmts, &assignment_to_block?(&1, var_atom)) do
      nil ->
        :error

      assign_idx ->
        {before, [assign_stmt | rest]} = Enum.split(stmts, assign_idx)

        case assign_stmt do
          {:=, assign_meta, [{^var_atom, _, nil}, block]} ->
            case block_type(block) do
              nil ->
                :error

              _ ->
                case find_continuation_using_var(rest, var_atom) do
                  {:ok, continuation, after_stmts} ->
                    {:ok, before, assign_meta, block, continuation, after_stmts}

                  :error ->
                    :error
                end
            end

          _ ->
            :error
        end
    end
  end

  # Check if a statement is `var = cond/case/if do ... end`
  defp assignment_to_block?({:=, _, [{var, _, nil}, block]}, var_atom)
       when var == var_atom,
       do: block_type(block) != nil

  defp assignment_to_block?(_, _), do: false

  # Determine block type (cond/case/if) from AST
  defp block_type({:cond, _, _}), do: :cond
  defp block_type({:case, _, _}), do: :case
  defp block_type({:if, _, _}), do: :if
  defp block_type(_), do: nil

  # Find the first statement after the assignment that uses var_atom
  defp find_continuation_using_var(stmts, var_atom) do
    case Enum.find_index(stmts, &uses_var?(&1, var_atom)) do
      nil ->
        :error

      idx ->
        {continuation_stmts, after_stmts} = Enum.split(stmts, idx + 1)
        continuation = hd(continuation_stmts)
        {:ok, continuation, after_stmts}
    end
  end

  # Check if an AST node uses a specific variable
  defp uses_var?(ast, var_atom) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {^var_atom, _, nil} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  # Given a block (cond/case/if) and a continuation expression that uses the
  # assigned variable, wrap each branch's body with the continuation.
  defp propagate_continuation({:cond, cond_meta, [branches_kw]}, var_atom, continuation) do
    new_branches = rewrite_cond_branches(branches_kw, var_atom, continuation)
    {:cond, cond_meta, [new_branches]}
  end

  defp propagate_continuation({:case, case_meta, [subject, branches_kw]}, var_atom, continuation) do
    new_branches = rewrite_branches(branches_kw, var_atom, continuation)
    {:case, case_meta, [subject, new_branches]}
  end

  defp propagate_continuation({:if, if_meta, [condition, branches_kw]}, var_atom, continuation) do
    new_branches =
      Enum.map(branches_kw, fn
        {{:__block__, meta, [:do]}, body} ->
          wrapped = replace_var_with_body(body, var_atom, continuation)
          {{:__block__, meta, [:do]}, wrapped}

        {{:__block__, meta, [:else]}, body} ->
          wrapped = replace_var_with_body(body, var_atom, continuation)
          {{:__block__, meta, [:else]}, wrapped}

        other ->
          other
      end)

    {:if, if_meta, [condition, new_branches]}
  end

  # Rewrite cond branches: each `->` body gets the continuation applied
  defp rewrite_cond_branches(branches_kw, var_atom, continuation) do
    Enum.map(branches_kw, fn
      {{:__block__, meta, [:do]}, branch_list} when is_list(branch_list) ->
        new_branch_list =
          Enum.map(branch_list, fn
            {:->, arrow_meta, [guards, body]} ->
              wrapped = replace_var_with_body(body, var_atom, continuation)
              {:->, arrow_meta, [guards, wrapped]}

            other ->
              other
          end)

        {{:__block__, meta, [:do]}, new_branch_list}

      other ->
        other
    end)
  end

  # Rewrite case branches (same structure as cond)
  defp rewrite_branches(branches_kw, var_atom, continuation) do
    Enum.map(branches_kw, fn
      {{:__block__, meta, [:do]}, branch_list} when is_list(branch_list) ->
        new_branch_list =
          Enum.map(branch_list, fn
            {:->, arrow_meta, [guards, body]} ->
              wrapped = replace_var_with_body(body, var_atom, continuation)
              {:->, arrow_meta, [guards, wrapped]}

            other ->
              other
          end)

        {{:__block__, meta, [:do]}, new_branch_list}

      other ->
        other
    end)
  end

  # Replace the variable reference in the continuation with the branch body.
  # For `wma1_val * 2` with body `Enum.sum(values)`, produces `Enum.sum(values) * 2`.
  defp replace_var_with_body(body, var_atom, continuation) do
    Macro.prewalk(continuation, fn
      {^var_atom, _, nil} -> body
      node -> node
    end)
  end
end
