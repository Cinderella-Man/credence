defmodule Credence.Semantic.FixCaseBranchAssignmentScope do
  @moduledoc """
  Fixes `undefined variable` errors caused by LLMs assigning a variable inside
  each branch of a `case` expression and then using it after the `case`.

  In Elixir, variables assigned inside a `case` branch are scoped to that branch
  — they do not leak out. LLMs (familiar with Python/JS) write:

      case x do
        :ok -> label = "success"
        :error -> label = "failure"
        _ -> label = "unknown"
      end
      String.upcase(label)

  The compiler emits `undefined variable "label"` because `label` is only
  defined inside each branch, not after the case block.

  The fix hoists the assignment outside the case, making each branch return
  just its value:

      label =
        case x do
          :ok -> "success"
          :error -> "failure"
          _ -> "unknown"
        end
      String.upcase(label)

  This preserves semantics: the case expression now returns the branch value,
  which is bound to `label` at the enclosing scope.
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
          {:ok, source} -> source_has_case_branch_assignment?(source, var_name)
          _ -> false
        end
    end
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :fix_case_branch_assignment_scope,
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
                case find_and_fix_case_branch_assignment(stmts, var_atom) do
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

  # Check if the source has a case block where all branches assign to var_name,
  # and var_name is used after the case block.
  defp source_has_case_branch_assignment?(source, var_name) do
    var_atom = String.to_atom(var_name)

    with {:ok, ast} <- Sourceror.parse_string(source) do
      {_ast, found} =
        Macro.prewalk(ast, false, fn
          {:__block__, _, stmts} = node, false when is_list(stmts) ->
            case has_case_branch_assignment?(stmts, var_atom) do
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

  # In a list of statements, find a case block where all branches assign to
  # var_atom, and var_atom is used in a subsequent statement.
  defp has_case_branch_assignment?(stmts, var_atom) do
    case Enum.find_index(stmts, &case_with_all_branches_assigning?(&1, var_atom)) do
      nil ->
        false

      case_idx ->
        {_before, [_case_stmt | rest]} = Enum.split(stmts, case_idx)
        match?({:ok, _, _}, find_continuation_using_var(rest, var_atom))
    end
  end

  # Find a case block and fix it by hoisting the common variable assignment out.
  defp find_and_fix_case_branch_assignment(stmts, var_atom) do
    case Enum.find_index(stmts, &case_with_all_branches_assigning?(&1, var_atom)) do
      nil ->
        :error

      case_idx ->
        {before, [case_stmt | rest]} = Enum.split(stmts, case_idx)

        case find_continuation_using_var(rest, var_atom) do
          {:ok, _continuation, _after_stmts} ->
            {:case, case_meta, [subject, branches_kw]} = case_stmt
            assign_meta = [line: Keyword.get(case_meta, :line, 1)]
            new_branches = rewrite_branches(branches_kw, var_atom)
            new_case = {:case, case_meta, [subject, new_branches]}
            new_assignment = {:=, assign_meta, [{var_atom, [], nil}, new_case]}
            {:ok, before ++ [new_assignment] ++ rest}

          :error ->
            :error
        end
    end
  end

  # Check if a statement is `case x do ... -> var = val ... end`
  # where ALL branches assign to var_atom.
  defp case_with_all_branches_assigning?({:case, _, [_, branches_kw]}, var_atom) do
    case extract_do_branches(branches_kw) do
      {:ok, branches} -> Enum.all?(branches, &branch_assigns_var?(&1, var_atom))
      _ -> false
    end
  end

  defp case_with_all_branches_assigning?(_, _), do: false

  defp extract_do_branches([{{:__block__, _, [:do]}, branches}]) when is_list(branches),
    do: {:ok, branches}

  defp extract_do_branches(_), do: :error

  # Check if a case branch assigns to var_atom as its last expression.
  defp branch_assigns_var?({:->, _, [_pattern, body]}, var_atom) do
    case body do
      {:=, _, [{var, _, nil}, _]} when var == var_atom ->
        true

      {:__block__, _, stmts} when is_list(stmts) ->
        case List.last(stmts) do
          {:=, _, [{var, _, nil}, _]} when var == var_atom -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  # Find the first statement after the case that uses var_atom.
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

  # Rewrite the branches of a case block, extracting the assigned variable
  # from each branch body and keeping just the value.
  defp rewrite_branches(branches_kw, var_atom) do
    Enum.map(branches_kw, fn
      {{:__block__, meta, [:do]}, branch_list} when is_list(branch_list) ->
        new_branch_list = Enum.map(branch_list, &rewrite_branch(&1, var_atom))
        {{:__block__, meta, [:do]}, new_branch_list}

      other ->
        other
    end)
  end

  # Rewrite a single branch, removing the assignment to var_atom and keeping
  # just the value.
  defp rewrite_branch({:->, arrow_meta, [pattern, body]}, var_atom) do
    new_body = extract_value_from_branch(body, var_atom)
    {:->, arrow_meta, [pattern, new_body]}
  end

  # Extract the value from a branch body that ends with `var = value`.
  defp extract_value_from_branch({:=, _, [{var, _, nil}, val]}, var_atom)
       when var == var_atom do
    val
  end

  defp extract_value_from_branch({:__block__, _block_meta, stmts}, var_atom)
       when is_list(stmts) do
    case List.last(stmts) do
      {:=, _, [{var, _, nil}, val]} when var == var_atom ->
        remaining = Enum.drop(stmts, -1)

        case remaining do
          [] -> val
          [single] -> single
          _ -> {:__block__, [], remaining ++ [val]}
        end

      _ ->
        {:__block__, [], stmts}
    end
  end

  defp extract_value_from_branch(body, _var_atom), do: body
end
