defmodule Credence.Pattern.NoRecursiveCaseWithoutEmptyListClause do
  @moduledoc """
  Detects `case` expressions that match on a list with only a `[head | tail]`
  clause and are missing the `[]` base case, which will crash at runtime on
  empty lists with `CaseClauseError`.

  ## Bad

      case stack do
        [top | rest] ->
          process(top, rest)
      end

  ## Good

      case stack do
        [] ->
          {[], MapSet.new()}
        [top | rest] ->
          process(top, rest)
      end
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # case expr do ... end
        {:case, meta, [_subject, kw]} = node, acc when is_list(kw) ->
          check_case(kw, node, acc, meta)

        # expr |> case do ... end
        {:case, meta, [kw]} = node, acc when is_list(kw) ->
          check_case(kw, node, acc, meta)

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    transformed = maybe_fix(ast)
    patches_between(ast, transformed)
  end

  # ── detection ──────────────────────────────────────────────────────

  defp check_case(kw, node, acc, meta) do
    case extract_do_clauses(kw) do
      {:ok, clauses} ->
        if cons_without_empty?(clauses) do
          {node, [build_issue(meta) | acc]}
        else
          {node, acc}
        end

      _ ->
        {node, acc}
    end
  end

  defp cons_without_empty?(clauses) do
    patterns = Enum.map(clauses, &extract_pattern/1)
    has_cons = Enum.any?(patterns, &cons_pattern?/1)
    has_empty = Enum.any?(patterns, &empty_list_pattern?/1)
    has_cons and not has_empty
  end

  # ── auto-fix ───────────────────────────────────────────────────────

  defp maybe_fix(ast) do
    Macro.postwalk(ast, fn
      # case expr do ... end
      {:case, meta, [subject, kw]} = node when is_list(kw) ->
        maybe_fix_case(node, meta, subject, kw)

      # expr |> case do ... end
      {:case, meta, [kw]} = node when is_list(kw) ->
        maybe_fix_case_pipe(node, meta, kw)

      node ->
        node
    end)
  end

  defp maybe_fix_case(node, meta, subject, kw) do
    case extract_do_clauses(kw) do
      {:ok, clauses} ->
        if cons_without_empty?(clauses) do
          new_clauses = [build_empty_list_clause() | clauses]
          {:case, meta, [subject, replace_do_clauses(kw, new_clauses)]}
        else
          node
        end

      _ ->
        node
    end
  end

  defp maybe_fix_case_pipe(node, meta, kw) do
    case extract_do_clauses(kw) do
      {:ok, clauses} ->
        if cons_without_empty?(clauses) do
          new_clauses = [build_empty_list_clause() | clauses]
          {:case, meta, [replace_do_clauses(kw, new_clauses)]}
        else
          node
        end

      _ ->
        node
    end
  end

  # Emit one patch per matching `case` node, rendering the whole node.
  # This avoids the stray-parens issue that `patches_from_ast_transform`
  # can produce when re-parsing a modified clause list.

  defp patches_between(same, same), do: []

  defp patches_between({:case, _, args_o} = orig, {:case, _, args_m} = modified) do
    if case_needs_fix?(orig) do
      case Sourceror.get_range(orig) do
        %Sourceror.Range{} = range ->
          [%{range: range, change: Credence.RuleHelpers.render_replacement(modified, range)}]

        _ ->
          []
      end
    else
      zip_recurse(args_o, args_m)
    end
  end

  defp patches_between({form, _, args_o}, {form, _, args_m})
       when is_list(args_o) and is_list(args_m) and length(args_o) == length(args_m) do
    zip_recurse(args_o, args_m)
  end

  defp patches_between([_ | _] = orig, [_ | _] = modified)
       when length(orig) == length(modified) do
    zip_recurse(orig, modified)
  end

  defp patches_between({a_o, b_o}, {a_m, b_m}) do
    patches_between(a_o, a_m) ++ patches_between(b_o, b_m)
  end

  defp patches_between(_, _), do: []

  defp zip_recurse(orig, modified) do
    orig
    |> Enum.zip(modified)
    |> Enum.flat_map(fn {o, m} -> patches_between(o, m) end)
  end

  defp case_needs_fix?({:case, _, [_subject, kw]}) when is_list(kw) do
    case extract_do_clauses(kw) do
      {:ok, clauses} -> cons_without_empty?(clauses)
      _ -> false
    end
  end

  defp case_needs_fix?({:case, _, [kw]}) when is_list(kw) do
    case extract_do_clauses(kw) do
      {:ok, clauses} -> cons_without_empty?(clauses)
      _ -> false
    end
  end

  defp case_needs_fix?(_), do: false

  # ── AST helpers ────────────────────────────────────────────────────

  defp extract_do_clauses([{{:__block__, _, [:do]}, clauses}]) when is_list(clauses) do
    {:ok, clauses}
  end

  defp extract_do_clauses(_), do: :error

  defp replace_do_clauses([{{:__block__, meta, [:do]}, _}], new_clauses) do
    [{{:__block__, meta, [:do]}, new_clauses}]
  end

  defp extract_pattern({:->, _, [[pattern], _body]}), do: pattern
  defp extract_pattern(_), do: nil

  # Match [head | tail] pattern — represented as
  # {:__block__, _, [[{:|, _, [head, tail]}]]}
  defp cons_pattern?({:__block__, _, [[{:|, _, [_, _]}]]}), do: true
  defp cons_pattern?(_), do: false

  # Match [] pattern — represented as {:__block__, _, [[]]}
  defp empty_list_pattern?({:__block__, _, [[]]}), do: true
  defp empty_list_pattern?(_), do: false

  # Build AST for: [] -> {[], MapSet.new()}
  defp build_empty_list_clause do
    empty_list = {:__block__, [], [[]]}
    mapset_new = {{:., [], [{:__aliases__, [], [:MapSet]}, :new]}, [], []}
    tuple_body = {:__block__, [], [{empty_list, mapset_new}]}
    {:->, [], [[empty_list], tuple_body]}
  end

  # ── issue ──────────────────────────────────────────────────────────

  defp build_issue(meta) do
    %Issue{
      rule: :no_recursive_case_without_empty_list_clause,
      message:
        "Case expression on a list has `[head | tail]` clause but no `[]` clause. " <>
          "This will crash with a `CaseClauseError` on empty lists. " <>
          "Add a `[] -> ...` base case.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
