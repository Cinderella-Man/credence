defmodule Credence.Semantic.FixIfBranchAssignmentScope do
  @moduledoc """
  Fixes `undefined variable` errors caused by LLMs assigning a variable inside
  each branch of a standalone `if` expression and then using it after `end`.

  In Elixir, variables assigned inside an `if`/`else` branch are scoped to that
  branch — they do not leak out. LLMs (familiar with Python/JS) write:

      if state.paused do
        new_service = Map.put(state, :timer_ref, nil)
        {:paused, new_service}
      else
        new_service = %{state | status: :active}
        {:active, new_service}
      end

      Map.put(new_service, :checked, true)

  The compiler emits `undefined variable "new_service"` because `new_service` is
  only defined inside each branch, not after the if block.

  The fix hoists the assignment outside the if, making each branch return the
  variable value:

      new_service =
        if state.paused do
          new_service = Map.put(state, :timer_ref, nil)
          {:paused, new_service}
          new_service
        else
          new_service = %{state | status: :active}
          {:active, new_service}
          new_service
        end

      Map.put(new_service, :checked, true)

  This preserves semantics: the if expression now returns the variable value from
  each branch, which is bound at the enclosing scope.
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
          {:ok, source} -> source_has_if_branch_assignment?(source, var_name)
          _ -> false
        end
    end
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :fix_if_branch_assignment_scope,
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
                case find_and_fix_if_branch_assignment(stmts, var_atom) do
                  {:ok, new_stmts} ->
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

  # Check if the source has a standalone if block where both branches assign to
  # var_name, and var_name is used after the if block.
  defp source_has_if_branch_assignment?(source, var_name) do
    var_atom = String.to_atom(var_name)

    with {:ok, ast} <- Sourceror.parse_string(source) do
      {_ast, found} =
        Macro.prewalk(ast, false, fn
          {:__block__, _, stmts} = node, false when is_list(stmts) ->
            case has_if_branch_assignment?(stmts, var_atom) do
              true -> {node, true}
              false -> {node, false}
            end

          node, acc ->
            {node, acc}
        end)

      found
    else
      _ -> false
    end
  end

  # In a list of statements, find a standalone if block where both branches
  # assign to var_atom, and var_atom is used in a subsequent statement.
  defp has_if_branch_assignment?(stmts, var_atom) do
    case Enum.find_index(stmts, &if_with_all_branches_assigning?(&1, var_atom)) do
      nil ->
        false

      if_idx ->
        {_before, [_if_stmt | rest]} = Enum.split(stmts, if_idx)
        match?({:ok, _, _}, find_continuation_using_var(rest, var_atom))
    end
  end

  # Find a standalone if block and fix it by hoisting the assignment and
  # appending the variable as the last expression in each branch.
  defp find_and_fix_if_branch_assignment(stmts, var_atom) do
    case Enum.find_index(stmts, &if_with_all_branches_assigning?(&1, var_atom)) do
      nil ->
        :error

      if_idx ->
        {before, [if_stmt | rest]} = Enum.split(stmts, if_idx)

        case find_continuation_using_var(rest, var_atom) do
          {:ok, _continuation, _after_stmts} ->
            {:if, if_meta, [condition, branches_kw]} = if_stmt
            assign_meta = [line: Keyword.get(if_meta, :line, 1)]
            new_branches = append_var_to_branches(branches_kw, var_atom)
            new_if = {:if, if_meta, [condition, new_branches]}
            new_assignment = {:=, assign_meta, [{var_atom, [], nil}, new_if]}
            {:ok, before ++ [new_assignment] ++ rest}

          :error ->
            :error
        end
    end
  end

  # Check if a statement is a standalone `if` where both branches assign to
  # var_atom.
  defp if_with_all_branches_assigning?({:if, _, [_, branches_kw]}, var_atom) do
    case extract_if_branches(branches_kw) do
      {:ok, do_body, else_body} ->
        branch_assigns_var?(do_body, var_atom) and branch_assigns_var?(else_body, var_atom)

      _ ->
        false
    end
  end

  defp if_with_all_branches_assigning?(_, _), do: false

  # Extract do and else bodies from if branches keyword list
  defp extract_if_branches(branches_kw) do
    do_branch =
      Enum.find(branches_kw, fn
        {{:__block__, _, [:do]}, _} -> true
        _ -> false
      end)

    else_branch =
      Enum.find(branches_kw, fn
        {{:__block__, _, [:else]}, _} -> true
        _ -> false
      end)

    case {do_branch, else_branch} do
      {{{:__block__, _, [:do]}, do_body}, {{:__block__, _, [:else]}, else_body}} ->
        {:ok, do_body, else_body}

      _ ->
        :error
    end
  end

  # Check if a branch body assigns to var_atom as any expression (not necessarily last).
  defp branch_assigns_var?({:=, _, [{var, _, nil}, _]}, var_atom) when var == var_atom, do: true

  defp branch_assigns_var?({:__block__, _, stmts}, var_atom) when is_list(stmts) do
    Enum.any?(stmts, fn
      {:=, _, [{var, _, nil}, _]} when var == var_atom -> true
      _ -> false
    end)
  end

  defp branch_assigns_var?(_, _), do: false

  # Append var_atom as the last expression in each if branch body.
  defp append_var_to_branches(branches_kw, var_atom) do
    Enum.map(branches_kw, fn
      {{:__block__, meta, [:do]}, body} ->
        new_body = append_var_to_body(body, var_atom)
        {{:__block__, meta, [:do]}, new_body}

      {{:__block__, meta, [:else]}, body} ->
        new_body = append_var_to_body(body, var_atom)
        {{:__block__, meta, [:else]}, new_body}

      other ->
        other
    end)
  end

  defp append_var_to_body({:__block__, meta, stmts}, var_atom) when is_list(stmts) do
    {:__block__, meta, stmts ++ [{var_atom, [], nil}]}
  end

  defp append_var_to_body(single, var_atom) do
    {:__block__, [], [single, {var_atom, [], nil}]}
  end

  # Find the first statement after the if that uses var_atom.
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

  # Check if an AST node uses a specific variable.
  defp uses_var?(ast, var_atom) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {^var_atom, _, nil} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end
end
