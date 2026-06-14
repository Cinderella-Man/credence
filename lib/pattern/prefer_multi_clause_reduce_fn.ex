defmodule Credence.Pattern.PreferMultiClauseReduceFn do
  @moduledoc """
  Detects `Enum.reduce/3` calls whose anonymous function has a single clause
  with nested `if/else` and rewrites them as multi-clause pattern-matching
  `fn` expressions.

  ## Bad

      Enum.reduce(list, {nil, 0}, fn element, {candidate, count} ->
        if count == 0 do
          {element, 1}
        else
          if element == candidate do
            {candidate, count + 1}
          else
            {candidate, count - 1}
          end
        end
      end)

  ## Good

      Enum.reduce(list, {nil, 0}, fn
        element, {candidate, 0} -> {element, 1}
        element, {candidate, count} when element == candidate -> {candidate, count + 1}
        _element, {candidate, count} -> {candidate, count - 1}
      end)

  Equality conditions whose LHS is a function parameter and RHS is a literal
  bound in the accumulator tuple become direct pattern matches; other equality
  conditions become `when` guards.
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case detect(node) do
          {:ok, meta} ->
            issue = %Issue{
              rule: :prefer_multi_clause_reduce_fn,
              message:
                "Enum.reduce anonymous function uses nested if/else. " <>
                  "Prefer multi-clause pattern matching.",
              meta: %{line: Keyword.get(meta, :line)}
            }

            {node, [issue | issues]}

          :error ->
            {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:fn, _, _} = node ->
        case detect(node) do
          {:ok, _meta} -> build_multi_clause_fn(node)
          :error -> node
        end

      node ->
        node
    end)
  end

  # ── detection ──────────────────────────────────────────────────────

  defp detect({:fn, meta, [{:->, _, [args, body]}]})
       when is_list(args) and length(args) == 2 do
    case extract_if_chain(body) do
      chain when is_list(chain) ->
        # Only flag if there are at least 2 actual conditions (nested if/else)
        # The chain includes a final {nil, else_branch} for the catch-all,
        # so we need at least 3 entries for a true nested case.
        conditions = Enum.filter(chain, fn {cond, _} -> not is_nil(cond) end)

        if length(conditions) >= 2 and
             Enum.any?(conditions, fn {cond, _} -> equality_condition?(cond) end) do
          {:ok, meta}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp detect(_), do: :error

  # ── fix ────────────────────────────────────────────────────────────

  defp build_multi_clause_fn({:fn, meta, [{:->, _, [args, body]}]}) do
    [first_param, acc_pattern] = args
    chain = extract_if_chain(body)
    acc_bindings = extract_bindings(acc_pattern)

    clauses =
      Enum.with_index(chain)
      |> Enum.map(fn {{condition, branch}, index} ->
        build_clause(first_param, acc_pattern, acc_bindings, condition, branch, index, chain)
      end)

    {:fn, meta, clauses}
  end

  defp build_clause(first_param, acc_pattern, acc_bindings, condition, branch, index, chain) do
    is_last = index == length(chain) - 1

    {new_first_param, new_acc_pattern, guard} =
      cond do
        is_last ->
          {underscore_var(first_param), acc_pattern, nil}

        equality_condition?(condition) ->
          {_, _, [lhs, rhs]} = condition
          lhs_name = var_name(lhs)
          rhs_name = var_name(rhs)

          cond do
            # var == literal -> pattern match. `Map.has_key?` already implies the
            # name is a real bound variable (var_name/1 returns an atom or nil,
            # and nil is never a binding key), so no `is_atom` guard is needed.
            Map.has_key?(acc_bindings, lhs_name) and is_nil(rhs_name) ->
              {first_param, replace_in_tuple(acc_pattern, lhs_name, rhs), nil}

            Map.has_key?(acc_bindings, rhs_name) and is_nil(lhs_name) ->
              {first_param, replace_in_tuple(acc_pattern, rhs_name, lhs), nil}

            # var == var (and any other equality) -> keep the comparison as a guard
            true ->
              {first_param, acc_pattern, condition}
          end

        true ->
          {first_param, acc_pattern, condition}
      end

    # In a multi-clause fn, the patterns list contains either:
    # - Two elements [param1, param2] for unguarded clauses
    # - One element {:when, _, [param1, param2, guard]} for guarded clauses
    pattern =
      if guard do
        [{:when, [], [new_first_param, new_acc_pattern, guard]}]
      else
        [new_first_param, new_acc_pattern]
      end

    {:->, [], [pattern, branch]}
  end

  # ── AST helpers ────────────────────────────────────────────────────

  # Extract a flat list of {condition, branch} from nested if/else.
  defp extract_if_chain({:if, _, [condition, branches]}) when is_list(branches) do
    do_branch = extract_branch(branches, :do)
    else_branch = extract_branch(branches, :else)

    case else_branch do
      nil ->
        [{condition, do_branch}]

      inner_if ->
        case extract_if_chain(inner_if) do
          chain when is_list(chain) -> [{condition, do_branch} | chain]
          _ -> [{condition, do_branch}, {nil, inner_if}]
        end
    end
  end

  defp extract_if_chain(_), do: :error

  defp extract_branch(branches, key) when is_list(branches) do
    Enum.find_value(branches, fn
      {{:__block__, _, [^key]}, val} -> val
      _ -> nil
    end)
  end

  # Check if condition is an equality comparison.
  defp equality_condition?({:==, _, [_, _]}), do: true
  defp equality_condition?(_), do: false

  # Extract variable name from AST node.
  defp var_name({name, _, ctx}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)),
    do: name

  defp var_name(_), do: nil

  # Extract variable bindings from a tuple pattern like {a, b}.
  defp extract_bindings({:__block__, _, [tuple]}) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.reduce(%{}, fn
      {name, _, ctx}, acc when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) ->
        Map.put(acc, name, true)

      _, acc ->
        acc
    end)
  end

  defp extract_bindings(_), do: %{}

  # Replace a variable in a tuple pattern with a new value.
  defp replace_in_tuple({:__block__, meta, [tuple]}, var_name, new_value) when is_tuple(tuple) do
    new_elements =
      tuple
      |> Tuple.to_list()
      |> Enum.map(fn
        {name, _, ctx} when name == var_name and (is_nil(ctx) or is_atom(ctx)) ->
          new_value

        other ->
          other
      end)

    {:__block__, meta, [List.to_tuple(new_elements)]}
  end

  defp replace_in_tuple(pattern, _, _), do: pattern

  # Create an underscore-prefixed version of a variable.
  defp underscore_var({name, meta, ctx}) when is_atom(name) do
    underscore_name =
      if String.starts_with?(to_string(name), "_") do
        name
      else
        :"_#{name}"
      end

    {underscore_name, meta, ctx}
  end

  defp underscore_var(other), do: other
end
