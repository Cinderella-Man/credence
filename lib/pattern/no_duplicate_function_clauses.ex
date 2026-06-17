defmodule Credence.Pattern.NoDuplicateFunctionClauses do
  @moduledoc """
  Detects duplicate function clauses with identical argument patterns.

  In Elixir, a second clause whose argument patterns are structurally identical
  to an earlier clause is unreachable — the first clause always matches first.
  The compiler emits "this clause cannot match because a previous clause always
  matches" which blocks compilation under `--warnings-as-errors`.

  Two clauses have identical patterns when their arguments normalize to the same
  structure: bare variables are positionally equivalent regardless of name, and
  literal/structural patterns must match exactly.

  ## Bad

      defmodule Example do
        def bar(x, y), do: {x, y}
        def bar(x, y), do: {x, y}
      end

  ## Good

      defmodule Example do
        def bar(x, y), do: {x, y}
      end
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:__block__, _, stmts} = node, acc when is_list(stmts) ->
          new_issues = detect_duplicate_clauses(stmts) ++ acc
          {node, new_issues}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    # Delete each duplicate clause surgically (whole-line), so the surrounding
    # code — unrelated module attributes, other clauses — keeps its exact source.
    # Re-rendering the whole block reformatted distant code (e.g. collapsed a
    # multi-line `@attr` keyword list).
    {_ast, patches} =
      Macro.prewalk(ast, [], fn
        {:__block__, _meta, stmts} = node, acc when is_list(stmts) ->
          dups = duplicate_clause_nodes(stmts)
          {node, acc ++ Enum.map(dups, &RuleHelpers.deletion_patch/1)}

        node, acc ->
          {node, acc}
      end)

    Enum.reject(patches, &is_nil/1)
  end

  # The duplicate clause nodes (every clause after the first of each signature) —
  # i.e. exactly the nodes `strip_duplicate_clauses/1` drops.
  defp duplicate_clause_nodes(stmts) do
    {_seen, dups} =
      Enum.reduce(stmts, {MapSet.new(), []}, fn
        {dt, _, _} = node, {seen, dups} when dt in [:def, :defp] ->
          case extract_clause_info(node) do
            {name, arity, args, guard} ->
              sig = signature(name, arity, args, guard)

              if MapSet.member?(seen, sig),
                do: {seen, [node | dups]},
                else: {MapSet.put(seen, sig), dups}

            nil ->
              {seen, dups}
          end

        _node, acc ->
          acc
      end)

    Enum.reverse(dups)
  end

  # Detect duplicate function clauses in a block of statements.
  defp detect_duplicate_clauses(stmts) do
    {_, issues} =
      Enum.reduce(stmts, {MapSet.new(), []}, fn
        {dt, _, _} = node, {seen, issues} when dt in [:def, :defp] ->
          case extract_clause_info(node) do
            {name, arity, args, guard} ->
              sig = signature(name, arity, args, guard)

              if MapSet.member?(seen, sig) do
                meta = elem(node, 1)
                issue = build_issue(meta, name, arity)
                {seen, [issue | issues]}
              else
                {MapSet.put(seen, sig), issues}
              end

            nil ->
              {seen, issues}
          end

        _node, acc ->
          acc
      end)

    issues
  end

  # Extract {name, arity, args, guard_parts} from a def/defp node.
  #
  # Requires a body (`[head, _body]`): a bodiless head (`def code(x)` — the
  # 1-element `[head]` declaration form for default args / docs) generates no
  # runtime clause and must not be compared against the real clauses below it.
  defp extract_clause_info({dt, _, [head, _body]}) when dt in [:def, :defp] do
    case head do
      {:when, _, [{name, _, args} | guard_parts]} when is_atom(name) and is_list(args) ->
        {name, length(args), args, guard_parts}

      {name, _, args} when is_atom(name) and is_list(args) ->
        {name, length(args), args, []}

      _ ->
        nil
    end
  end

  defp extract_clause_info(_), do: nil

  # Build a comparable signature for a clause. Args and guards are normalized
  # together with a shared binding map so that variable identity is preserved:
  # the Nth distinct variable name becomes `{:v, N}`, and a *repeated* name reuses
  # its placeholder. This keeps `def f(x, x)` (a non-linear equality constraint)
  # distinct from `def f(a, b)` — without it, both collapse to two placeholders
  # and reachable clauses get flagged as duplicates.
  defp signature(name, arity, args, guard_parts) do
    {normalized_args, state} = Enum.map_reduce(args, {%{}, 0}, &normalize_node/2)
    {normalized_guards, _state} = Enum.map_reduce(guard_parts, state, &normalize_node/2)
    {name, arity, normalized_args, normalized_guards}
  end

  # Stateful normalization threading `{name => placeholder_index, next_index}`.
  # Bare `_` is always a fresh placeholder (each underscore is independent).
  defp normalize_node({:_, _, ctx}, {names, n}) when is_atom(ctx) do
    {{:v, n}, {names, n + 1}}
  end

  defp normalize_node({var, _, ctx}, {names, n}) when is_atom(var) and is_atom(ctx) do
    case names do
      %{^var => idx} -> {{:v, idx}, {names, n}}
      _ -> {{:v, n}, {Map.put(names, var, n), n + 1}}
    end
  end

  # Module attribute `@name` — the name is a constant identifier, not a bindable
  # variable; keep it literal so e.g. `@joins` and `@from_join_opts` (and the
  # guards that reference them) do not normalize equal.
  defp normalize_node({:@, _, [{name, _, ctx}]}, state) when is_atom(name) and is_atom(ctx) do
    {{:@, name}, state}
  end

  defp normalize_node({form, _meta, args}, state) when is_list(args) do
    {normalized, state} = Enum.map_reduce(args, state, &normalize_node/2)
    {{form, normalized}, state}
  end

  defp normalize_node({left, right}, state) do
    {nl, state} = normalize_node(left, state)
    {nr, state} = normalize_node(right, state)
    {{nl, nr}, state}
  end

  defp normalize_node(list, state) when is_list(list) do
    Enum.map_reduce(list, state, &normalize_node/2)
  end

  defp normalize_node(other, state), do: {other, state}

  defp build_issue(meta, name, arity) do
    %Issue{
      rule: :no_duplicate_function_clauses,
      message:
        "Duplicate function clause for `#{name}/#{arity}`. " <>
          "The second clause has identical argument patterns and is unreachable.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
