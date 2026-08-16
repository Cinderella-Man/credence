defmodule Credence.Pattern.NoRedundantListTraversal do
  @moduledoc """
  Detects multiple traversals of the same list that could be merged into
  a single pass.

  Separate `Enum.min/1` and `Enum.max/1` calls can be replaced by the
  built-in `Enum.min_max/1`. Similarly, `length/1` + `Enum.sum/1` or
  other pairs on the same list are flagged as a hint, though the
  `count + sum` pair is not auto-fixed (see below).

  Only flags calls that are:
  - bare assignments (`var = func(list)`) in the same block
  - arity-1 calls on a plain variable (not an expression or field access)
  - on the same variable with no rebinding between them

  ## Detected functions

      length/1          →  :count
      Enum.count/1      →  :count
      Enum.sum/1        →  :sum
      Enum.min/1        →  :min
      Enum.max/1        →  :max

  ## Auto-fixable pairs

      Enum.min + Enum.max           →  Enum.min_max/1

  The `count + sum` pair is flagged but NOT auto-fixed — merging `Enum.sum/1`
  + `length/1` into a manual `Enum.reduce/3` with a tuple accumulator is a
  readability downgrade. The built-in functions are the idiomatic pattern.

  Other combinations are flagged but not auto-fixed.

  ## Bad

      minimum = Enum.min(numbers)
      maximum = Enum.max(numbers)

  ## Good

      {minimum, maximum} = Enum.min_max(numbers)
  """

  use Credence.Pattern.Rule
  # Safe in all three families: the only fixable pair is `Enum.min(v)` +
  # `Enum.max(v)` on the same bare variable in one block, replaced by
  # `Enum.min_max(v)`; `Enum.*` is never a DSL-expression construct, and the
  # count+sum reduce (the branch that would build `c + 1`/`s + x`) is excluded
  # from @fixable_pairs and unreachable from the fix. The source scan flags this
  # rule because the construct appears in it, but the matcher cannot reach a DSL
  # expression, so the deliberate answer is the empty list rather than an
  # allowlist entry — the fixture-level oracle does not flag it at all.
  @impl true
  def unsafe_in_dsl, do: []
  alias Credence.Issue
  alias Credence.RuleHelpers

  # Pairs we know how to auto-fix
  # Note: [:count, :sum] is NOT fixable — merging Enum.sum + length into a
  # manual Enum.reduce with a tuple accumulator is a readability downgrade.
  # Enum.sum/1 + length/1 is the idiomatic Elixir pattern for computing means.
  # The check still flags it as a "consider merging" hint, but no auto-fix.
  @fixable_pairs [
    MapSet.new([:min, :max])
  ]

  # Enum functions we track (arity 1 only — arity 2 has different semantics)
  @tracked_enum_funcs [:count, :sum, :min, :max]

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:__block__, _meta, statements} = node, acc when is_list(statements) ->
          {node, build_issues(statements) ++ acc}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)
    groups = collect_all_fixable_groups(ast)

    if groups == [] do
      []
    else
      RuleHelpers.patches_from_ast_transform(ast, source, fn input ->
        Macro.postwalk(input, &maybe_rewrite_block/1)
      end)
    end
  end

  # Scans a block's direct children for bare traversal assignments.
  # Returns a list of entry maps, each: %{result_var, list_var, type, label, index, line, mode}
  defp scan_statements(statements) do
    statements
    |> Enum.with_index()
    |> Enum.flat_map(fn {stmt, idx} ->
      case scan_statement(stmt, idx) do
        {:ok, entry} -> [entry]
        :skip -> []
      end
    end)
  end

  # Matches: result_var = traversal_func(list_var)
  # Only bare assignments where the RHS is exactly the call (not nested).
  defp scan_statement({:=, meta, [lhs, rhs]}, index) do
    with {:ok, result_var} <- plain_variable_name(lhs),
         {:ok, list_var, type, label} <- identify_call(rhs) do
      {:ok,
       %{
         result_var: result_var,
         list_var: list_var,
         type: type,
         label: label,
         index: index,
         line: Keyword.get(meta, :line),
         mode: :bare
       }}
    else
      _ -> :skip
    end
  end

  defp scan_statement(_, _), do: :skip

  # Scans statements for inline traversal calls (calls embedded in
  # larger expressions). Skips statements already captured as bare
  # assignments AND discarded assignments (_ = ...) to avoid false positives.
  defp scan_inline_calls(statements, bare_indices) do
    statements
    |> Enum.with_index()
    |> Enum.flat_map(fn {stmt, idx} ->
      if idx in bare_indices or discarded_assignment?(stmt) do
        []
      else
        find_inline_traversals(stmt, idx)
      end
    end)
  end

  defp discarded_assignment?({:=, _, [{:_, _, _}, _rhs]}), do: true
  defp discarded_assignment?(_), do: false

  # Finds tracked traversal calls in a statement WITHOUT descending
  # into block bodies (do/else/catch/rescue/after clauses). This
  # prevents cross-scope false positives from calls inside nested
  # if/case/cond/fn/def bodies.
  defp find_inline_traversals(stmt, stmt_index) do
    calls = shallow_collect_calls(stmt)

    Enum.map(calls, fn {list_var, type, label, line} ->
      %{
        result_var: generated_name(type),
        list_var: list_var,
        type: type,
        label: label,
        index: stmt_index,
        line: line,
        mode: :inline
      }
    end)
  end

  defp shallow_collect_calls(ast) do
    shallow_collect_calls(ast, []) |> Enum.reverse()
  end

  defp shallow_collect_calls(ast, acc) do
    # Check if THIS node is a tracked call
    acc =
      case identify_call(ast) do
        {:ok, list_var, type, label} ->
          line =
            case ast do
              {_, meta, _} when is_list(meta) -> Keyword.get(meta, :line)
              _ -> nil
            end

          [{list_var, type, label, line} | acc]

        :skip ->
          acc
      end

    # Recurse into children, skipping keyword block bodies
    case ast do
      {_form, _meta, args} when is_list(args) ->
        Enum.reduce(args, acc, &walk_child_shallow/2)

      {left, right} ->
        walk_child_shallow(left, walk_child_shallow(right, acc))

      list when is_list(list) ->
        if keyword_block_list?(list) do
          acc
        else
          Enum.reduce(list, acc, &walk_child_shallow/2)
        end

      _ ->
        acc
    end
  end

  defp walk_child_shallow(child, acc), do: shallow_collect_calls(child, acc)

  # Detects keyword lists that represent block bodies: [do: ...], [do: ..., else: ...], etc.
  @block_keys [:do, :else, :catch, :rescue, :after]

  defp keyword_block_list?([{key, _} | _]) when key in @block_keys, do: true

  defp keyword_block_list?([{{:__block__, _, [key]}, _} | _]) when key in @block_keys,
    do: true

  defp keyword_block_list?(_), do: false

  # Combines bare assignment scan with inline call scan.
  defp scan_all_calls(statements) do
    bare = scan_statements(statements)
    bare_indices = MapSet.new(bare, & &1.index)
    inline = scan_inline_calls(statements, bare_indices)
    bare ++ inline
  end

  # Generated variable names for inline calls that need a fresh binding.
  defp generated_name(:count), do: :count
  defp generated_name(:sum), do: :sum
  defp generated_name(:min), do: :minimum
  defp generated_name(:max), do: :maximum

  # Groups entries by list variable and returns only valid groups:
  # 2+ distinct aggregate types, no rebinding between first and last.
  # Skips groups where all entries are inline calls in the same statement —
  # e.g. `Enum.sum(x) / length(x)` is a natural compound expression, not a
  # redundancy worth merging into a manual reduce.
  defp find_valid_groups(statements) do
    scan_all_calls(statements)
    |> Enum.group_by(& &1.list_var)
    |> Enum.flat_map(fn {list_var, entries} ->
      distinct_types = entries |> Enum.map(& &1.type) |> Enum.uniq()

      if length(distinct_types) >= 2 do
        sorted = Enum.sort_by(entries, & &1.index)
        first_idx = hd(sorted).index
        last_idx = List.last(sorted).index

        if all_inline_same_statement?(sorted) or
             variable_rebound?(statements, list_var, first_idx, last_idx) do
          []
        else
          [%{list_var: list_var, entries: sorted}]
        end
      else
        []
      end
    end)
  end

  # Returns true when every entry is an inline call (not a bare assignment)
  # and they all share the same statement index. Such pairs are part of a
  # single natural expression (e.g. `avg = Enum.sum(x) / length(x)`) and
  # should not be flagged or merged.
  defp all_inline_same_statement?(entries) do
    Enum.all?(entries, &(&1.mode == :inline)) and
      entries |> Enum.map(& &1.index) |> Enum.uniq() |> length() == 1
  end

  # length(var) — Kernel BIF
  defp identify_call({:length, _, [arg]}) do
    with {:ok, var_name} <- plain_variable_name(arg) do
      {:ok, var_name, :count, "length/1"}
    end
  end

  # Enum.func(var) — tracked functions, arity 1 only
  defp identify_call({{:., _, [module, func_ref]}, _, [arg]}) do
    func = unwrap_atom(func_ref)

    if enum_module?(module) and func in @tracked_enum_funcs do
      with {:ok, var_name} <- plain_variable_name(arg) do
        {:ok, var_name, func, "Enum.#{func}/1"}
      end
    else
      :skip
    end
  end

  defp identify_call(_), do: :skip

  # Returns {:ok, name} for a plain variable, :skip for anything else
  # (underscore, pattern, expression, field access, etc.)
  defp plain_variable_name({name, _, context})
       when is_atom(name) and is_atom(context) and name != :_ do
    {:ok, name}
  end

  defp plain_variable_name(_), do: :skip

  # Sourceror wraps bare atoms in {:__block__, meta, [atom]}.
  defp unwrap_atom({:__block__, _, [atom]}) when is_atom(atom), do: atom
  defp unwrap_atom(atom) when is_atom(atom), do: atom
  defp unwrap_atom(_), do: nil

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?(_), do: false

  # Returns true if `var_name` is bound on the LHS of any assignment
  # between statement indices from_idx (exclusive) and to_idx (exclusive).
  defp variable_rebound?(statements, var_name, from_idx, to_idx) do
    statements
    |> Enum.with_index()
    |> Enum.any?(fn {stmt, idx} ->
      idx > from_idx and idx < to_idx and rebinds_variable?(stmt, var_name)
    end)
  end

  defp rebinds_variable?({:=, _, [lhs, _rhs]}, var_name) do
    ast_binds_name?(lhs, var_name)
  end

  defp rebinds_variable?(_, _), do: false

  # Recursively checks if an AST node (the LHS of =) binds a variable name.
  # Handles plain variables, list patterns, tuple patterns, map patterns, etc.
  defp ast_binds_name?({name, _, context}, target)
       when is_atom(name) and is_atom(context),
       do: name == target

  defp ast_binds_name?({_, _, args}, target) when is_list(args),
    do: Enum.any?(args, &ast_binds_name?(&1, target))

  defp ast_binds_name?(list, target) when is_list(list),
    do: Enum.any?(list, &ast_binds_name?(&1, target))

  defp ast_binds_name?(_, _), do: false

  defp build_issues(statements) do
    find_valid_groups(statements)
    |> Enum.map(fn %{list_var: list_var, entries: entries} ->
      labels = Enum.map_join(entries, " and ", & &1.label)

      %Issue{
        rule: :no_redundant_list_traversal,
        message:
          "#{labels} both traverse `#{list_var}` — " <>
            "consider merging into a single pass.",
        meta: %{line: hd(entries).line}
      }
    end)
  end

  # Pre-scan: collects all fixable groups across the entire AST.
  # Used to short-circuit Sourceror.to_string() when nothing to fix.
  defp collect_all_fixable_groups(ast) do
    {_ast, groups} =
      Macro.prewalk(ast, [], fn
        {:__block__, _meta, statements} = node, acc when is_list(statements) ->
          fixable = find_fixable_groups(statements)
          {node, fixable ++ acc}

        node, acc ->
          {node, acc}
      end)

    groups
  end

  defp find_fixable_groups(statements) do
    find_valid_groups(statements)
    |> Enum.filter(fn group ->
      types = group.entries |> Enum.map(& &1.type) |> MapSet.new()

      length(group.entries) == 2 and
        Enum.any?(@fixable_pairs, &MapSet.equal?(&1, types))
    end)
  end

  # Postwalk callback: rewrites a __block__ if it contains fixable groups.
  defp maybe_rewrite_block({:__block__, meta, statements} = node)
       when is_list(statements) do
    fixable = find_fixable_groups(statements)

    if fixable == [] do
      node
    else
      {:__block__, meta, apply_fixes(statements, fixable)}
    end
  end

  defp maybe_rewrite_block(node), do: node

  # Applies all fixes to a statement list: handles bare-bare,
  # bare-inline, inline-bare, and inline-inline entry pairs.
  defp apply_fixes(statements, groups) do
    {replacements, removals, inline_rewrites, insertions} =
      Enum.reduce(groups, {%{}, MapSet.new(), %{}, %{}}, fn group, acc ->
        build_fix_plan(group, acc)
      end)

    statements
    |> Enum.with_index()
    |> Enum.flat_map(fn {stmt, idx} ->
      cond do
        # Insert merged call BEFORE this statement, then rewrite inline calls
        Map.has_key?(insertions, idx) ->
          rewritten = apply_inline_rewrites(stmt, Map.get(inline_rewrites, idx, []))
          [insertions[idx], rewritten]

        # Replace this bare assignment with the merged call
        Map.has_key?(replacements, idx) ->
          [replacements[idx]]

        # Remove this bare assignment (merged into another position)
        idx in removals ->
          []

        # Rewrite inline calls in this statement
        Map.has_key?(inline_rewrites, idx) ->
          [apply_inline_rewrites(stmt, inline_rewrites[idx])]

        true ->
          [stmt]
      end
    end)
  end

  # Builds the fix plan for a single group based on entry modes.
  defp build_fix_plan(group, {repls, rems, rewrites, inserts}) do
    [first, second] = group.entries
    merged = build_replacement(group.list_var, first, second)

    case {first.mode, second.mode} do
      {:bare, :bare} ->
        # Existing: replace first bare with merged, remove second bare
        {Map.put(repls, first.index, merged), MapSet.put(rems, second.index), rewrites, inserts}

      {:bare, :inline} ->
        # Replace bare with merged, rewrite inline call in second's statement
        new_rewrites = add_rewrite(rewrites, second)
        {Map.put(repls, first.index, merged), rems, new_rewrites, inserts}

      {:inline, :bare} ->
        # Insert merged before first's statement, rewrite inline call, remove bare
        new_inserts = Map.put(inserts, first.index, merged)
        new_rewrites = add_rewrite(rewrites, first)
        {repls, MapSet.put(rems, second.index), new_rewrites, new_inserts}

      {:inline, :inline} ->
        # Insert merged before first's statement, rewrite both inline calls
        new_inserts = Map.put(inserts, first.index, merged)
        new_rewrites = rewrites |> add_rewrite(first) |> add_rewrite(second)
        {repls, rems, new_rewrites, new_inserts}
    end
  end

  defp add_rewrite(rewrites, entry) do
    spec = %{type: entry.type, list_var: entry.list_var, new_var: entry.result_var}
    Map.update(rewrites, entry.index, [spec], &[spec | &1])
  end

  # Walks a statement AST replacing inline traversal calls with variable references.
  defp apply_inline_rewrites(stmt, rewrites) do
    Enum.reduce(rewrites, stmt, fn %{type: type, list_var: list_var, new_var: new_var}, ast ->
      replace_call_with_var(ast, type, list_var, new_var)
    end)
  end

  # Replaces the first matching traversal call in an AST with a plain variable.
  defp replace_call_with_var(ast, target_type, target_list_var, new_var) do
    Macro.postwalk(ast, fn node ->
      case identify_call(node) do
        {:ok, ^target_list_var, ^target_type, _label} ->
          {new_var, [], nil}

        _ ->
          node
      end
    end)
  end

  defp build_replacement(list_var, first, second) do
    types = MapSet.new([first.type, second.type])

    cond do
      MapSet.equal?(types, MapSet.new([:min, :max])) ->
        build_min_max_ast(list_var, first, second)

      MapSet.equal?(types, MapSet.new([:count, :sum])) ->
        build_reduce_ast(list_var, first, second)
    end
  end

  # {min_var, max_var} = Enum.min_max(list_var)
  # Always min first, max second — matching Enum.min_max/1 return order.
  defp build_min_max_ast(list_var, entry_a, entry_b) do
    {min_entry, max_entry} =
      if entry_a.type == :min, do: {entry_a, entry_b}, else: {entry_b, entry_a}

    Sourceror.parse_string!(
      "{#{min_entry.result_var}, #{max_entry.result_var}} = Enum.min_max(#{list_var})"
    )
  end

  # {var_a, var_b} = Enum.reduce(list_var, {init_a, init_b}, fn x, {a, b} -> {upd_a, upd_b} end)
  # Tuple position follows source order (first-appearing entry first).
  defp build_reduce_ast(list_var, first, second) do
    entries = Enum.sort_by([first, second], & &1.index)

    parts =
      Enum.map(entries, fn entry ->
        case entry.type do
          :count -> %{var: entry.result_var, init: "0", acc: "c", update: "c + 1"}
          :sum -> %{var: entry.result_var, init: "0", acc: "s", update: "s + x"}
        end
      end)

    lhs = Enum.map_join(parts, ", ", &"#{&1.var}")
    inits = Enum.map_join(parts, ", ", & &1.init)
    accs = Enum.map_join(parts, ", ", & &1.acc)
    updates = Enum.map_join(parts, ", ", & &1.update)

    Sourceror.parse_string!(
      "{#{lhs}} = Enum.reduce(#{list_var}, {#{inits}}, fn x, {#{accs}} -> {#{updates}} end)"
    )
  end
end
