defmodule Credence.Pattern.NoEnumAtNegativeIndex do
  @moduledoc """
  Detects `Enum.at/2` called with a negative integer literal index.

  Elixir lists are singly-linked, so `Enum.at(list, -1)` traverses the
  entire list to reach the last element. Calling `Enum.at(list, -2)` does
  the same to reach the second-to-last, and so on — each call pays O(n).

  When multiple negative-index accesses target the same list, the
  cost multiplies unnecessarily.

  ## Bad

      last = Enum.at(sorted_list, -1)
      one_before_last = Enum.at(sorted_list, -2)

      value = sorted |> Enum.at(-1)

  ## Good

      # For multiple tail elements, reverse once and pattern-match
      sorted_list_reversed = Enum.reverse(sorted_list)
      [last, one_before_last | _] = sorted_list_reversed

      # For a single last element, use List.last/1
      value = List.last(sorted)

  ## Auto-fix

  When multiple assignments access the same list variable with negative
  indices within the same function, the fixer groups them into a single
  `Enum.reverse/1` call and a pattern match (up to depth 5).

  A lone `Enum.at(x, -1)` is rewritten to `List.last(x)`.

  A lone `Enum.at(x, -N)` where N > 1 is rewritten to a reverse +
  pattern match on a single variable.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @max_fixable_depth 5

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Direct call: Enum.at(list, <neg>)
        {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, meta, [_list, idx_node]} = node, issues ->
          case extract_negative_index(idx_node) do
            {:ok, index} -> {node, [build_issue(meta, index) | issues]}
            :error -> {node, issues}
          end

        # Pipe: ... |> Enum.at(<neg>)
        {:|>, _, [_lhs, {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, meta, [idx_node]}]} = node,
        issues ->
          case extract_negative_index(idx_node) do
            {:ok, index} -> {node, [build_issue(meta, index) | issues]}
            :error -> {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)
    RuleHelpers.patches_from_ast_transform(ast, source, &transform_ast/1)
  end

  # Two-pass transform:
  #
  #   Pass 1 (prewalk): rewrite each `:__block__` to consolidate bare
  #     `lhs = Enum.at(list_var, -N)` assignments by list_var into a
  #     single `Enum.reverse/1` + destructure, OR replace lone `-1`
  #     accesses with `List.last/1`. Also handles inline `-N>1` calls
  #     in expression position by prepending reverse+pattern statements
  #     to the block and substituting the inline calls with bound names.
  #
  #   Pass 2 (postwalk): replace any remaining bare `Enum.at(x, -1)`
  #     / `|> Enum.at(-1)` calls with `List.last/1` — this catches
  #     single-expression bodies (`def f(x), do: Enum.at(x, -1)`) that
  #     never go through a `:__block__`.
  defp transform_ast(ast) do
    ast
    |> Macro.prewalk(&rewrite_block_or_pass/1)
    |> Macro.postwalk(&replace_inline_minus_one/1)
  end

  defp rewrite_block_or_pass({:__block__, _meta, []} = node), do: node

  defp rewrite_block_or_pass({:__block__, meta, stmts}) when is_list(stmts) do
    {:__block__, meta, rewrite_statements(stmts)}
  end

  defp rewrite_block_or_pass(node), do: node

  # Only rewrite when the list arg is a plain variable — match the original
  # regex's conservative scope (`Enum.at(\w+, -1)`). Complex expressions
  # like `Enum.at(Map.get(data, :items), -1)` are deliberately preserved.
  defp replace_inline_minus_one(
         {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [list_arg, idx_node]} = node
       ) do
    with true <- simple_var?(list_arg),
         {:ok, -1} <- extract_negative_index(idx_node) do
      list_last_call(list_arg)
    else
      _ -> node
    end
  end

  defp replace_inline_minus_one(
         {:|>, pipe_meta, [lhs, {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [idx_node]}]} =
           node
       ) do
    case extract_negative_index(idx_node) do
      {:ok, -1} -> {:|>, pipe_meta, [lhs, list_last_pipe_call()]}
      _ -> node
    end
  end

  defp replace_inline_minus_one(node), do: node

  defp simple_var?({name, _, ctx}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)),
    do: true

  defp simple_var?(_), do: false

  # Block-level rewrite — handles bare assignments + inline `-N>1`.
  defp rewrite_statements(stmts) do
    indexed = Enum.with_index(stmts)
    bare = collect_bare_entries(indexed)

    # Bare-assignment groups by list_var (sorted by stmt order)
    bare_groups =
      bare
      |> Enum.group_by(& &1.list_var)
      |> Map.values()
      |> Enum.map(&Enum.sort_by(&1, fn e -> e.stmt_idx end))

    {bare_actions, bare_handled} = plan_bare_actions(bare_groups)

    # Statements not consumed by bare-grouping: scan for inline `-N>1`
    # calls that need block-level prepends.
    inline_plan = plan_inline_actions(indexed, bare_handled)

    apply_plan(stmts, bare_actions, inline_plan)
  end

  defp collect_bare_entries(indexed) do
    Enum.flat_map(indexed, fn {stmt, idx} ->
      case classify_bare(stmt) do
        {:ok, lhs, list_var, index} when index >= -@max_fixable_depth ->
          [%{lhs_var: lhs, list_var: list_var, index: index, stmt_idx: idx, stmt: stmt}]

        _ ->
          []
      end
    end)
  end

  # `lhs = Enum.at(list_var, -N)` direct form
  defp classify_bare(
         {:=, _,
          [
            {lhs, _, lhs_ctx},
            {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [{list_var, _, list_ctx}, idx_node]}
          ]}
       )
       when is_atom(lhs) and is_atom(list_var) and
              (is_nil(lhs_ctx) or is_atom(lhs_ctx)) and
              (is_nil(list_ctx) or is_atom(list_ctx)) do
    with {:ok, idx} <- extract_negative_index(idx_node), do: {:ok, lhs, list_var, idx}
  end

  # `lhs = list_var |> Enum.at(-N)` piped form
  defp classify_bare(
         {:=, _,
          [
            {lhs, _, lhs_ctx},
            {:|>, _,
             [
               {list_var, _, list_ctx},
               {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [idx_node]}
             ]}
          ]}
       )
       when is_atom(lhs) and is_atom(list_var) and
              (is_nil(lhs_ctx) or is_atom(lhs_ctx)) and
              (is_nil(list_ctx) or is_atom(list_ctx)) do
    with {:ok, idx} <- extract_negative_index(idx_node), do: {:ok, lhs, list_var, idx}
  end

  defp classify_bare(_), do: :error

  # Decide what to do per bare group:
  #   single -1: rewrite the assignment in-place to `lhs = List.last(list_var)`
  #   multi or non-(-1) with unique LHS vars: replace first stmt with
  #     [reverse, pattern], delete the others
  defp plan_bare_actions(groups) do
    Enum.reduce(groups, {%{}, MapSet.new()}, fn entries, {actions, handled} ->
      case bare_group_action(entries) do
        {:list_last, entry} ->
          {Map.put(actions, entry.stmt_idx, {:replace, [list_last_assign(entry)]}),
           MapSet.put(handled, entry.stmt_idx)}

        {:reverse_pattern, first, others, list_var, pattern_elems} ->
          first_repl = reverse_and_pattern(list_var, pattern_elems)

          {Map.put(actions, first.stmt_idx, {:replace, first_repl})
           |> then(fn acc ->
             Enum.reduce(others, acc, fn e, a -> Map.put(a, e.stmt_idx, :delete) end)
           end),
           MapSet.union(
             handled,
             MapSet.new([first.stmt_idx | Enum.map(others, & &1.stmt_idx)])
           )}

        :skip ->
          {actions, handled}
      end
    end)
  end

  # Single entry of -1: convert to List.last
  defp bare_group_action([%{index: -1} = entry]), do: {:list_last, entry}

  # Single entry with deeper index, OR multiple entries: build reverse+pattern.
  defp bare_group_action(entries) do
    lhs_vars = Enum.map(entries, & &1.lhs_var)

    if length(lhs_vars) != length(Enum.uniq(lhs_vars)) do
      :skip
    else
      by_depth = Map.new(entries, fn e -> {abs(e.index), e.lhs_var} end)
      max_depth = entries |> Enum.map(&abs(&1.index)) |> Enum.max()

      pattern_elems =
        for pos <- 1..max_depth do
          case Map.get(by_depth, pos) do
            nil -> {:_, [], nil}
            name -> {name, [], nil}
          end
        end

      [first | others] = Enum.sort_by(entries, & &1.stmt_idx)
      {:reverse_pattern, first, others, first.list_var, pattern_elems}
    end
  end

  # Inline-call planning: walk each remaining statement for `Enum.at(var, -N)`
  # calls (any -N including -1) and prepend `reversed = Enum.reverse(var)` +
  # destructure, then substitute calls with the new variable references.
  defp plan_inline_actions(indexed, bare_handled) do
    Enum.flat_map(indexed, fn {stmt, idx} ->
      if MapSet.member?(bare_handled, idx) do
        []
      else
        case collect_inline_calls(stmt) do
          [] ->
            []

          calls ->
            [{idx, plan_inline_for_statement(stmt, calls)}]
        end
      end
    end)
    |> Map.new()
  end

  defp plan_inline_for_statement(stmt, calls) do
    by_var = Enum.group_by(calls, & &1.list_var)

    {prepends_rev, subst_map} =
      Enum.reduce(by_var, {[], %{}}, fn {list_var, var_calls}, {prepends, subst} ->
        indices = var_calls |> Enum.map(& &1.index) |> Enum.uniq() |> Enum.sort()

        cond do
          # Single -1 only — handled later by the postwalk pass.
          indices == [-1] ->
            {prepends, subst}

          # Deeper or mixed — emit reverse+pattern, build substitution map.
          Enum.all?(indices, &(&1 >= -@max_fixable_depth)) ->
            depths = Enum.map(indices, &abs/1)
            max_depth = Enum.max(depths)

            depth_to_name =
              Map.new(depths, fn d ->
                {d, String.to_atom("#{Atom.to_string(list_var)}_neg#{d}")}
              end)

            pattern_elems =
              for pos <- 1..max_depth do
                case Map.get(depth_to_name, pos) do
                  nil -> {:_, [], nil}
                  name -> {name, [], nil}
                end
              end

            new_subst =
              Enum.reduce(indices, subst, fn idx, acc ->
                Map.put(acc, {list_var, idx}, Map.fetch!(depth_to_name, abs(idx)))
              end)

            {reverse_and_pattern(list_var, pattern_elems) ++ prepends, new_subst}

          true ->
            {prepends, subst}
        end
      end)

    rewritten =
      if map_size(subst_map) == 0 do
        stmt
      else
        substitute_enum_at_calls(stmt, subst_map)
      end

    {Enum.reverse(prepends_rev), rewritten}
  end

  # Walk statement and collect `Enum.at(list_var, -N)` calls (direct or piped).
  # Stops at nested function bodies (`def`, `defp`, `fn`) — calls inside them
  # belong to that scope's own `:__block__` rewrite, not this block's.
  defp collect_inline_calls(stmt), do: Enum.reverse(do_collect_inline(stmt, []))

  defp do_collect_inline({def_type, _, _}, acc) when def_type in [:def, :defp], do: acc
  defp do_collect_inline({:fn, _, _}, acc), do: acc
  # Nested `:__block__` is a child scope — let its own block walk handle it.
  defp do_collect_inline({:__block__, _, stmts}, acc) when is_list(stmts) and length(stmts) > 1,
    do: acc

  defp do_collect_inline(
         {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [{list_var, _, list_ctx}, idx_node]},
         acc
       )
       when is_atom(list_var) and (is_nil(list_ctx) or is_atom(list_ctx)) do
    case extract_negative_index(idx_node) do
      {:ok, idx} -> [%{list_var: list_var, index: idx} | acc]
      :error -> acc
    end
  end

  defp do_collect_inline(
         {:|>, _,
          [
            {list_var, _, list_ctx},
            {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [idx_node]}
          ]},
         acc
       )
       when is_atom(list_var) and (is_nil(list_ctx) or is_atom(list_ctx)) do
    case extract_negative_index(idx_node) do
      {:ok, idx} -> [%{list_var: list_var, index: idx} | acc]
      :error -> acc
    end
  end

  defp do_collect_inline({_form, _meta, args}, acc) when is_list(args) do
    Enum.reduce(args, acc, &do_collect_inline/2)
  end

  defp do_collect_inline({left, right}, acc) do
    do_collect_inline(right, do_collect_inline(left, acc))
  end

  defp do_collect_inline(list, acc) when is_list(list) do
    Enum.reduce(list, acc, &do_collect_inline/2)
  end

  defp do_collect_inline(_, acc), do: acc

  defp substitute_enum_at_calls(stmt, subst) do
    Macro.prewalk(stmt, fn
      {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [{list_var, _, _}, idx_node]} = node
      when is_atom(list_var) ->
        with {:ok, idx} <- extract_negative_index(idx_node),
             {:ok, new_name} <- Map.fetch(subst, {list_var, idx}) do
          {new_name, [], nil}
        else
          _ -> node
        end

      {:|>, _,
       [
         {list_var, _, _},
         {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [idx_node]}
       ]} = node
      when is_atom(list_var) ->
        with {:ok, idx} <- extract_negative_index(idx_node),
             {:ok, new_name} <- Map.fetch(subst, {list_var, idx}) do
          {new_name, [], nil}
        else
          _ -> node
        end

      node ->
        node
    end)
  end

  defp apply_plan(stmts, bare_actions, inline_plan) do
    stmts
    |> Enum.with_index()
    |> Enum.flat_map(fn {stmt, idx} ->
      cond do
        action = Map.get(bare_actions, idx) ->
          case action do
            {:replace, new_stmts} -> new_stmts
            :delete -> []
          end

        plan = Map.get(inline_plan, idx) ->
          {prepends, new_stmt} = plan
          prepends ++ [new_stmt]

        true ->
          [stmt]
      end
    end)
  end

  # AST builders

  defp list_last_call(list_arg) do
    {{:., [], [{:__aliases__, [], [:List]}, :last]}, [], [list_arg]}
  end

  defp list_last_pipe_call do
    {{:., [], [{:__aliases__, [], [:List]}, :last]}, [], []}
  end

  defp list_last_assign(%{lhs_var: lhs, list_var: list_var}) do
    {:=, [], [{lhs, [], nil}, list_last_call({list_var, [], nil})]}
  end

  defp reverse_and_pattern(list_var, pattern_elems) do
    reversed_name = String.to_atom("#{Atom.to_string(list_var)}_reversed")

    reverse_stmt =
      {:=, [],
       [
         {reversed_name, [], nil},
         {{:., [], [{:__aliases__, [], [:Enum]}, :reverse]}, [], [{list_var, [], nil}]}
       ]}

    pattern_list = build_cons_pattern(pattern_elems)

    pattern_stmt = {:=, [], [pattern_list, {reversed_name, [], nil}]}

    [reverse_stmt, pattern_stmt]
  end

  # Build `[a, b, ... | _]` AST
  defp build_cons_pattern(elems) do
    tail = {:_, [], nil}

    [{:|, [], [List.last(elems), tail]} | []]
    |> then(fn last_segment ->
      front = Enum.drop(elems, -1)
      front ++ last_segment
    end)
  end

  defp extract_negative_index({:-, _, [{:__block__, _, [n]}]}) when is_integer(n) and n > 0,
    do: {:ok, -n}

  defp extract_negative_index(_), do: :error

  defp build_issue(meta, index) do
    message =
      if index == -1 do
        """
        `Enum.at(list, -1)` traverses the entire list to reach the last element.

        Use `List.last/1` instead — it is semantically clearer and avoids the
        overhead of the generic `Enum.at/2` negative-index handling.
        """
      else
        """
        `Enum.at(list, #{index})` traverses the entire list to reach the element \
        #{abs(index)} positions from the end.

        Consider reversing the list once and pattern-matching the elements you need:

            [last, second_to_last | _rest] = Enum.reverse(list)
        """
      end

    %Issue{
      rule: :no_enum_at_negative_index,
      message: message,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
