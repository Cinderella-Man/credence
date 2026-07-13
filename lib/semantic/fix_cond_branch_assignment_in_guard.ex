defmodule Credence.Semantic.FixCondBranchAssignmentInGuard do
  @moduledoc """
  Fixes `undefined variable` errors caused by LLMs assigning a variable inside
  a `cond` branch body and referencing it in the *next* branch's guard.

  In Elixir, each `cond` branch is its own scope. LLMs (accustomed to
  sequential imperative code) write:

      cond do
        condition_a ->
          var = expr
        uses_var_in_guard(var) ->
          :result
        true ->
          :default
      end

  expecting `var` from the first branch to be visible in the second branch's
  guard. The compiler emits `undefined variable "var"`.

  This is distinct from `FixCondBranchAssignmentScope`, which handles variables
  assigned in a branch body and used *after* the entire `cond` block.

  The deterministic fix restructures the offending `cond` into nested `if`
  expressions that restore the intended scoping:

      if condition_a do
        var = expr
        if uses_var_in_guard(var) do
          :result
        else
          :default
        end
      else
        :default
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{severity: :error, message: msg, file: file})
      when is_binary(msg) and is_binary(file) do
    case extract_var_name(msg) do
      nil ->
        false

      var_name ->
        case File.read(file) do
          {:ok, source} -> source_has_guard_assignment_pattern?(source, var_name)
          _ -> false
        end
    end
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :fix_cond_branch_assignment_in_guard,
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
              {:cond, _meta, [[{_do_kw, branches}]]} = node, false ->
                case find_guard_assignment_pair(branches, var_atom) do
                  {:ok, first_idx, second_idx, default_branch} ->
                    new_ast = restructure_to_ifs(branches, first_idx, second_idx, default_branch)
                    {new_ast, true}

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

  # Check if the source has a cond branch whose body assigns `var_name` and a
  # subsequent branch whose guard references that variable.
  defp source_has_guard_assignment_pattern?(source, var_name) do
    var_atom = String.to_atom(var_name)

    with {:ok, ast} <- Sourceror.parse_string(source) do
      {_ast, found} =
        Macro.prewalk(ast, false, fn
          {:cond, _, [[{_, branches}]]} = node, false ->
            case find_guard_assignment_pair(branches, var_atom) do
              {:ok, _, _, _} -> {node, true}
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

  # Given the branches keyword list of a cond, find a pair where:
  # - branch[i] body assigns `var_atom`
  # - branch[i+1] guard references `var_atom`
  #
  # Returns {:ok, first_idx, second_idx, default_branch} or :error.
  defp find_guard_assignment_pair(branches, var_atom) do
    branch_list = extract_branch_list(branches)

    case Enum.find_index(branch_list, fn {:->, _, [[_guard], body]} ->
           assigns_var?(body, var_atom)
         end) do
      nil ->
        :error

      assign_idx ->
        remaining = Enum.drop(branch_list, assign_idx + 1)

        case Enum.find_index(remaining, fn {:->, _, [[guard], _body]} ->
               var_in_ast?(guard, var_atom)
             end) do
          nil ->
            :error

          rel_idx ->
            default_branch = find_default_branch(branch_list)
            {:ok, assign_idx, assign_idx + 1 + rel_idx, default_branch}
        end
    end
  end

  # Extract the flat list of -> branches from the cond keyword structure
  defp extract_branch_list({:__block__, _, branches}), do: branches
  defp extract_branch_list(branches) when is_list(branches), do: branches
  defp extract_branch_list(_), do: []

  # Check if an AST node assigns a specific variable (top-level match)
  defp assigns_var?({:=, _, [{var, _, nil}, _rhs]}, var_atom) when var == var_atom, do: true
  defp assigns_var?({:__block__, _, stmts}, var_atom) when is_list(stmts) do
    Enum.any?(stmts, &assigns_var?(&1, var_atom))
  end
  defp assigns_var?(_, _), do: false

  # Check if an AST node references a variable
  defp var_in_ast?(ast, var_atom) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {^var_atom, _, nil} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  # Find the `true -> default` branch
  defp find_default_branch(branches) do
    Enum.find(branches, fn
      {:->, _, [[{:__block__, _, [true]}], body]} -> body
      _ -> false
    end)
  end

  # Restructure the cond into nested if expressions.
  #
  # Sourceror needs `do: [line: _, column: _]` and `end: [line: _, column: _]`
  # metadata on the `if` node to emit the block form (`if ... do ... end`)
  # instead of the keyword shorthand (`if ..., do: ...`).
  defp restructure_to_ifs(branches, first_idx, second_idx, default_branch) do
    branch_list = extract_branch_list(branches)

    {:->, _, [[first_guard], first_body]} = Enum.at(branch_list, first_idx)
    {:->, _, [[second_guard], second_body]} = Enum.at(branch_list, second_idx)

    # Build the else block from the default branch (or nil if no default)
    else_block =
      case default_branch do
        {:->, _, [[_guard], body]} -> body
        nil -> {:__block__, [], [nil]}
      end

    # Build inner if: second_guard ? second_body : else_block
    inner_if = build_if_block(second_guard, second_body, else_block)

    # Build outer if: first_guard ? (first_body + inner_if) : else_block
    then_block =
      case first_body do
        {:__block__, meta, stmts} -> {:__block__, meta, stmts ++ [inner_if]}
        single -> {:__block__, [], [single, inner_if]}
      end

    build_if_block(first_guard, then_block, else_block)
  end

  # Build an `if` AST node with the metadata Sourceror needs to emit block form.
  defp build_if_block(condition, then_body, else_body) do
    if_meta = [
      trailing_comments: [],
      leading_comments: [],
      do: [line: 0, column: 1],
      end: [line: 0, column: 1],
      line: 0,
      column: 1
    ]

    do_entry = {{:__block__, [trailing_comments: [], leading_comments: [], line: 0, column: 1], [:do]}, then_body}
    else_entry = {{:__block__, [trailing_comments: [], leading_comments: [], line: 0, column: 1], [:else]}, else_body}

    {:if, if_meta, [condition, [do_entry, else_entry]]}
  end
end
