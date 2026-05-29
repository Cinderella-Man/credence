defmodule Credence.Pattern.InconsistentParamNames do
  @moduledoc """
  Detects functions where the same positional parameter uses different
  variable names across clauses.

  ## Why this matters

  LLMs generate function clauses semi-independently, often drifting
  parameter names between clauses of the same function:

      # Flagged — first arg is "current" in one clause, "prev" in another
      defp do_fibonacci(current, _next, 0), do: current
      defp do_fibonacci(prev, current, steps), do: do_fibonacci(current, prev + current, steps - 1)

      # Consistent — same name at each position across all clauses
      defp do_fibonacci(prev, _current, 0), do: prev
      defp do_fibonacci(prev, current, steps), do: do_fibonacci(current, prev + current, steps - 1)

  Inconsistent names make the reader question whether the function is
  correct — if the first argument is called `current` in one clause and
  `prev` in another, which is it?

  ## Auto-fix strategy

  The first clause establishes canonical base names. Subsequent clauses
  are renamed to match. Underscore prefixes are preserved: if a clause
  uses `_banana` and the canonical base is `number`, it becomes `_number`.

  Bare `_` and non-variable patterns (literals, destructuring) at a
  given position cause that position to be skipped entirely.

  ## Pattern-match equality between arguments

  When the same variable name appears at multiple argument positions
  within one clause — top-level or nested inside a tuple, list, map,
  struct, or binary — Elixir enforces equality between those positions:

      def validate(errors, q, ans, ans), do: errors  # 3rd arg must equal 4th
      def lookup(id, %User{id: id}), do: id          # top-level arg must equal nested field

  Such names are load-bearing. Renaming one occurrence breaks the
  equality; renaming a free name in another clause to the same target
  invents an equality that wasn't there. Whenever any clause in a
  group has such an intra-clause name sharing, every position that
  participates is skipped — for both detection and renaming — so the
  rule never produces an unsafe fix.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    clauses = collect_clauses(ast)

    clauses
    |> Enum.group_by(fn {name, arity, _args, _meta, _def_type} -> {name, arity} end)
    |> Enum.flat_map(fn {_key, group} -> analyze_group(group) end)
    |> Enum.sort_by(fn issue -> issue.meta[:line] || 0 end)
  end

  defp collect_clauses(ast) do
    {_ast, clauses} =
      Macro.prewalk(ast, [], fn node, acc ->
        case extract_clause_info(node) do
          {:ok, clause} -> {node, [clause | acc]}
          :error -> {node, acc}
        end
      end)

    Enum.reverse(clauses)
  end

  defp extract_clause_info({def_type, meta, [{:when, _, [{fn_name, _, args}, _guard]}, _body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    {:ok, {fn_name, length(args), args, meta, def_type}}
  end

  defp extract_clause_info({def_type, meta, [{fn_name, _, args}, _body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    {:ok, {fn_name, length(args), args, meta, def_type}}
  end

  defp extract_clause_info(_), do: :error

  defp analyze_group(clauses) when length(clauses) < 2, do: []

  defp analyze_group(clauses) do
    [{name, arity, _, _, def_type} | _] = clauses
    args_lists = Enum.map(clauses, fn {_, _, args, _, _} -> args end)
    meta = clauses |> hd() |> elem(3)
    pinned = pinned_positions_across_clauses(args_lists)

    Enum.flat_map(0..(arity - 1), fn pos ->
      if MapSet.member?(pinned, pos) do
        []
      else
        base_names_at_pos =
          args_lists
          |> Enum.map(fn args -> Enum.at(args, pos) end)
          |> Enum.map(&extract_base_name/1)

        if Enum.any?(base_names_at_pos, &is_nil/1) do
          # Bare `_`, pattern, or literal at this position in some clause — skip
          []
        else
          unique_bases = Enum.uniq(base_names_at_pos)

          if length(unique_bases) > 1 do
            [build_issue(def_type, name, arity, pos + 1, unique_bases, meta)]
          else
            []
          end
        end
      end
    end)
  end

  # Union of pinned positions across every clause in the group. If any one
  # clause encodes pattern-match equality at a position, that position is
  # excluded everywhere — both for detection and renaming.
  @spec pinned_positions_across_clauses([[Macro.t()]]) :: MapSet.t(non_neg_integer())
  defp pinned_positions_across_clauses(args_lists) do
    Enum.reduce(args_lists, MapSet.new(), fn args, acc ->
      MapSet.union(acc, pinned_positions_in_clause(args))
    end)
  end

  # Within one clause: collect every variable base name from each arg's
  # full pattern (including nested), then flag positions whose name set
  # intersects names that occur 2+ times total across all args.
  @spec pinned_positions_in_clause([Macro.t()]) :: MapSet.t(non_neg_integer())
  defp pinned_positions_in_clause(args) do
    names_per_pos =
      args
      |> Enum.with_index()
      |> Enum.map(fn {arg, idx} -> {idx, collect_base_names_in_pattern(arg)} end)

    shared =
      names_per_pos
      |> Enum.flat_map(fn {_idx, names} -> names end)
      |> Enum.frequencies()
      |> Enum.reduce(MapSet.new(), fn
        {name, count}, acc when count >= 2 -> MapSet.put(acc, name)
        _, acc -> acc
      end)

    Enum.reduce(names_per_pos, MapSet.new(), fn {idx, names}, acc ->
      if Enum.any?(names, &MapSet.member?(shared, &1)) do
        MapSet.put(acc, idx)
      else
        acc
      end
    end)
  end

  defp collect_base_names_in_pattern(pattern) do
    {_, names} =
      Macro.prewalk(pattern, [], fn
        {name, _, ctx} = node, acc when is_atom(name) and is_atom(ctx) ->
          case base_name_of_atom(name) do
            nil -> {node, acc}
            base -> {node, [base | acc]}
          end

        node, acc ->
          {node, acc}
      end)

    names
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:__block__, block_meta, stmts} when is_list(stmts) ->
        {:__block__, block_meta, fix_block_stmts(stmts)}

      node ->
        node
    end)
  end

  defp fix_block_stmts(stmts) do
    stmts
    |> chunk_consecutive_clauses()
    |> Enum.flat_map(fn
      [single] -> [single]
      group -> fix_clause_group(group)
    end)
  end

  defp chunk_consecutive_clauses(stmts) do
    {result, _key, group} =
      Enum.reduce(stmts, {[], nil, []}, fn stmt, {result, current_key, current_group} ->
        key = extract_fn_key(stmt)

        cond do
          key != nil and key == current_key ->
            # Same function — extend group
            {result, current_key, current_group ++ [stmt]}

          key != nil ->
            # Different function — flush old group, start new
            {flush_group(result, current_group), key, [stmt]}

          current_key != nil and clause_passthrough?(stmt) ->
            # Module attribute (e.g. `@impl`, `@doc`, `@spec`) between two
            # clauses of the same function — keep the group alive and carry
            # the attribute inside it. `fix_clause_group/1` walks the group
            # and re-interleaves attributes at their original positions, so
            # `@impl true` lines stay where the user put them.
            {result, current_key, current_group ++ [stmt]}

          true ->
            # Not a def/defp and not a passthrough attribute — flush any
            # group and emit standalone.
            {flush_group(result, current_group) ++ [[stmt]], nil, []}
        end
      end)

    flush_group(result, group)
  end

  defp clause_passthrough?({:@, _, _}), do: true
  defp clause_passthrough?(_), do: false

  defp flush_group(result, []), do: result
  defp flush_group(result, group), do: result ++ [group]

  defp extract_fn_key({def_type, _, [{:when, _, [{fn_name, _, args}, _guard]}, _body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    {def_type, fn_name, length(args)}
  end

  defp extract_fn_key({def_type, _, [{fn_name, _, args}, _body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    {def_type, fn_name, length(args)}
  end

  defp extract_fn_key(_), do: nil

  defp fix_clause_group(group) do
    defs = Enum.filter(group, fn stmt -> extract_fn_key(stmt) != nil end)

    if length(defs) < 2 do
      group
    else
      [first | rest] = defs
      args_lists = Enum.map(defs, &extract_args/1)
      pinned = pinned_positions_across_clauses(args_lists)

      canonical =
        first
        |> canonical_base_names()
        |> Enum.with_index()
        |> Enum.map(fn {name, idx} ->
          if MapSet.member?(pinned, idx), do: nil, else: name
        end)

      renamed_defs = [first | Enum.map(rest, &rename_clause(&1, canonical))]

      {result, _} =
        Enum.reduce(group, {[], renamed_defs}, fn stmt, {acc, remaining} ->
          if extract_fn_key(stmt) != nil do
            [next_def | tail] = remaining
            {[next_def | acc], tail}
          else
            {[stmt | acc], remaining}
          end
        end)

      Enum.reverse(result)
    end
  end

  defp canonical_base_names(clause) do
    clause
    |> extract_args()
    |> Enum.map(&extract_base_name/1)
  end

  defp extract_args({def_type, _, [{:when, _, [{_name, _, args}, _guard]}, _body]})
       when def_type in [:def, :defp],
       do: args

  defp extract_args({def_type, _, [{_name, _, args}, _body]})
       when def_type in [:def, :defp],
       do: args

  defp rename_clause(clause, canonical) do
    args = extract_args(clause)
    rename_map = build_rename_map(args, canonical)

    if map_size(rename_map) == 0 do
      clause
    else
      apply_renames(clause, rename_map)
    end
  end

  defp build_rename_map(args, canonical) do
    Enum.zip(args, canonical)
    |> Enum.reduce(%{}, fn
      # Canonical says skip — don't touch this position
      {_arg, nil}, map ->
        map

      # Variable at this position — check if rename needed
      {{name, _, ctx}, base}, map when is_atom(name) and is_atom(ctx) ->
        current_base = base_name_of_atom(name)

        cond do
          # Bare _ — skip
          current_base == nil ->
            map

          # Already matches canonical
          current_base == base ->
            map

          # Needs rename — preserve underscore prefix
          true ->
            new_name =
              if String.starts_with?(Atom.to_string(name), "_"),
                do: String.to_atom("_" <> base),
                else: String.to_atom(base)

            Map.put(map, name, new_name)
        end

      # Pattern or literal — skip
      _, map ->
        map
    end)
  end

  defp apply_renames(clause, rename_map) do
    Macro.postwalk(clause, fn
      {name, meta, ctx} when is_atom(name) and is_atom(ctx) ->
        case Map.get(rename_map, name) do
          nil -> {name, meta, ctx}
          new_name -> {new_name, meta, ctx}
        end

      node ->
        node
    end)
  end

  # Returns the base name (without leading underscore) as a string,
  # or nil for bare `_` and non-variable nodes.
  defp extract_base_name({name, _, ctx}) when is_atom(name) and is_atom(ctx) do
    base_name_of_atom(name)
  end

  defp extract_base_name(_), do: nil

  defp base_name_of_atom(name) do
    str = Atom.to_string(name)

    cond do
      str == "_" -> nil
      String.starts_with?(str, "_") -> String.trim_leading(str, "_")
      true -> str
    end
  end

  defp build_issue(def_type, name, arity, position, conflicting_bases, meta) do
    names_str =
      Enum.map_join(conflicting_bases, ", ", &"`#{&1}`")

    %Issue{
      rule: :inconsistent_param_names,
      message: """
      Inconsistent parameter names in `#{def_type} #{name}/#{arity}` \
      at position #{position}: #{names_str}.

      Using different names for the same parameter across clauses makes \
      the code harder to follow. Choose one name and use it consistently, \
      or use `_` to indicate the parameter is unused in that clause.\
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
