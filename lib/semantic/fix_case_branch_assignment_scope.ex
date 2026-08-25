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

  ## Matching vs fixing

  `match?/1` sees only the diagnostic (no source), so it claims every
  `undefined variable "name"` error; `fix/2` then verifies the source actually
  has the shape above and no-ops otherwise, and the `should_report?/2` phase
  hook keeps `analyze` honest by reporting an issue only when the fix would
  rewrite the source. The fix is anchored to the
  diagnostic: it rewrites a `case` only when the *first* statement after it
  that uses the variable spans the diagnostic's line. That anchor is what makes
  the rewrite safe — the compiler reporting the variable undefined at that
  line proves no earlier binding exists in that scope, so hoisting cannot
  shadow or change any live binding.

  ## Deliberately skipped (no fix)

    * a branch that binds the variable through a pattern (`{:ok, label} = …`)
      — hoisting would change the case's value from the tuple to the variable;
    * a branch that does not end in `var = value` — the case's value would
      change;
    * a `case` whose subject itself uses the variable — the rewrite could not
      resolve the error;
    * a diagnostic whose line does not fall on the statement using the
      variable after the case — the error belongs to some other occurrence.

  ## Bad

      defmodule MFCBAS do
        def classify(x) do
          case x do
            :ok -> label = "success"
            :error -> label = "failure"
            _ -> label = "unknown"
          end

          String.upcase(label)
        end
      end

  ## Good

      defmodule MFCBAS do
        def classify(x) do
          label =
            case x do
              :ok -> "success"
              :error -> "failure"
              _ -> "unknown"
            end

          String.upcase(label)
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  # The full diagnostic text for this error is exactly the phrase below —
  # anchored so a snippet-bearing message from another error cannot match.
  @message_re ~r/\Aundefined variable "([a-zA-Z_][a-zA-Z0-9_]*[?!]?)"\z/

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    extract_var_name(msg) != nil
  end

  def match?(_), do: false

  @doc """
  Phase hook (`Credence.Semantic.match_rules/2`): report an issue only when
  `fix/2` would actually rewrite the source. `match?/1` sees just the
  diagnostic, so without this gate every undefined-variable error in a file
  (typos included) would be attributed to this rule.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :fix_case_branch_assignment_scope,
      message: msg,
      meta: %{line: line(position)}
    }
  end

  @impl true
  def fix(source, %{message: msg} = diagnostic) do
    with var_name when is_binary(var_name) <- extract_var_name(msg),
         err_line when is_integer(err_line) <- line(Map.get(diagnostic, :position)),
         {:ok, ast} <- Sourceror.parse_string(source) do
      var_atom = String.to_atom(var_name)

      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:__block__, meta, stmts} = node, false when is_list(stmts) ->
            case hoist_case_assignment(stmts, var_atom, err_line) do
              {:ok, new_stmts} -> {{:__block__, meta, new_stmts}, true}
              :error -> {node, false}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  defp extract_var_name(msg) do
    case Regex.run(@message_re, msg) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp line({l, _col}) when is_integer(l), do: l
  defp line(l) when is_integer(l), do: l
  defp line(_), do: nil

  # In a list of statements, find a case where all branches end in
  # `var_atom = value`, followed by a statement that uses var_atom and spans
  # the diagnostic's line; hoist the assignment out of the case.
  defp hoist_case_assignment(stmts, var_atom, err_line) do
    case Enum.find_index(stmts, &case_with_all_branches_assigning?(&1, var_atom)) do
      nil ->
        :error

      case_idx ->
        {before, [case_stmt | rest]} = Enum.split(stmts, case_idx)
        {:case, case_meta, [subject, branches_kw]} = case_stmt

        with false <- uses_var?(subject, var_atom),
             {:ok, continuation} <- first_stmt_using_var(rest, var_atom),
             true <- stmt_spans_line?(continuation, err_line) do
          new_branches = rewrite_branches(branches_kw, var_atom)
          new_case = {:case, case_meta, [subject, new_branches]}
          assign_meta = [line: Keyword.get(case_meta, :line, 1)]
          new_assignment = {:=, assign_meta, [{var_atom, [], nil}, new_case]}
          {:ok, before ++ [new_assignment] ++ rest}
        else
          _ -> :error
        end
    end
  end

  # Check if a statement is `case x do ... -> var = val ... end`
  # where ALL branches assign to var_atom.
  defp case_with_all_branches_assigning?({:case, _, [_, branches_kw]}, var_atom) do
    case extract_do_branches(branches_kw) do
      {:ok, branches} ->
        branches != [] and Enum.all?(branches, &branch_assigns_var?(&1, var_atom))

      _ ->
        false
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

  defp branch_assigns_var?(_, _), do: false

  defp first_stmt_using_var(stmts, var_atom) do
    case Enum.find(stmts, &uses_var?(&1, var_atom)) do
      nil -> :error
      stmt -> {:ok, stmt}
    end
  end

  defp stmt_spans_line?(stmt, err_line) do
    case Sourceror.get_range(stmt) do
      %{start: start, end: finish} ->
        err_line >= Keyword.get(start, :line, 0) and err_line <= Keyword.get(finish, :line, 0)

      _ ->
        false
    end
  rescue
    _ -> false
  end

  # Check if an AST node uses a specific variable.
  defp uses_var?(ast, var_atom) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {kind, _, _}, acc
        when kind in [:def, :defp, :defmacro, :defmacrop, :defmodule, :defprotocol, :defimpl] ->
          {nil, acc}

        {^var_atom, _, nil} = node, _acc ->
          {node, true}

        node, acc ->
          {node, acc}
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

  defp rewrite_branch({:->, arrow_meta, [pattern, body]}, var_atom) do
    new_body = extract_value_from_branch(body, var_atom)
    {:->, arrow_meta, [pattern, new_body]}
  end

  defp rewrite_branch(other, _var_atom), do: other

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
          _ -> {:__block__, [], remaining ++ [val]}
        end

      _ ->
        {:__block__, [], stmts}
    end
  end

  defp extract_value_from_branch(body, _var_atom), do: body
end
