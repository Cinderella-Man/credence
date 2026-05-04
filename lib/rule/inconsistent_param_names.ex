defmodule Credence.Rule.InconsistentParamNames do
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
  """

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

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

    Enum.flat_map(0..(arity - 1), fn pos ->
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
    end)
  end

  @impl true
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      {:__block__, block_meta, stmts} when is_list(stmts) ->
        {:__block__, block_meta, fix_block_stmts(stmts)}

      node ->
        node
    end)
    |> Sourceror.to_string()
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

          true ->
            # Not a def/defp — flush any group, emit standalone
            {flush_group(result, current_group) ++ [[stmt]], nil, []}
        end
      end)

    flush_group(result, group)
  end

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

  defp fix_clause_group([first | rest]) do
    canonical = canonical_base_names(first)

    fixed_rest =
      Enum.map(rest, fn clause ->
        rename_clause(clause, canonical)
      end)

    [first | fixed_rest]
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
