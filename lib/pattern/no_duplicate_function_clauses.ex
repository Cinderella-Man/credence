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
          new =
            for {dup, name, arity} <- duplicate_clauses(stmts),
                do: build_issue(elem(dup, 1), name, arity)

          {node, new ++ acc}

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
          dups = for {dup, _name, _arity} <- duplicate_clauses(stmts), do: dup
          {node, acc ++ Enum.map(dups, &RuleHelpers.deletion_patch/1)}

        node, acc ->
          {node, acc}
      end)

    Enum.reject(patches, &is_nil/1)
  end

  # The duplicate clauses in a block: every def/defp clause after the first with
  # the same full signature. Returns `[{node, name, arity}]`. Used by both check
  # (→ issues) and fix (→ deletion patches), so they agree exactly.
  #
  # The signature is computed in source order while tracking module-attribute
  # *redefinitions*: a clause that references `@ops` is distinct from an earlier
  # same-head clause if `@ops` was reassigned between them (its guard then filters
  # a different set). The signature also includes the (normalized) BODY — two
  # clauses that share a head but have different bodies are NOT collapsed: the
  # later one is the author's likely copy-paste bug, not safe-to-delete noise.
  defp duplicate_clauses(stmts) do
    {_seen, _vers, dups} =
      Enum.reduce(stmts, {MapSet.new(), %{}, []}, fn stmt, {seen, vers, dups} ->
        case attr_assignment_name(stmt) do
          {:ok, attr} ->
            {seen, Map.update(vers, attr, 1, &(&1 + 1)), dups}

          :error ->
            case clause_signature(stmt, vers) do
              {:ok, sig, name, arity} ->
                if MapSet.member?(seen, sig),
                  do: {seen, vers, [{stmt, name, arity} | dups]},
                  else: {MapSet.put(seen, sig), vers, dups}

              :error ->
                {seen, vers, dups}
            end
        end
      end)

    Enum.reverse(dups)
  end

  # A module-attribute assignment `@name value` (inner has a non-empty arg list),
  # as opposed to a usage `@name` (inner is a context atom).
  defp attr_assignment_name({:@, _, [{name, _, args}]})
       when is_atom(name) and is_list(args) and args != [],
       do: {:ok, name}

  defp attr_assignment_name(_), do: :error

  # Build `{:ok, signature, name, arity}` for a def/defp clause, or `:error`.
  #
  # Requires a body (`[head, body]`): a bodiless head (`def code(x)` — the
  # 1-element `[head]` declaration form for default args / docs) generates no
  # runtime clause and must not be compared against the real clauses below it.
  defp clause_signature({dt, _meta, [head, body]}, attr_versions) when dt in [:def, :defp] do
    # A head containing `unquote(...)` is macro-generated: the surface AST
    # collapses every `unquote(var)` to the same placeholder, so distinct clauses
    # (e.g. `def f(unquote(lower))` vs `def f(unquote(upper))`) look identical and
    # would be wrongly deleted. The real patterns are only known after expansion.
    if contains_unquote?(head) do
      :error
    else
      case head_parts(head) do
        {name, args, guard_parts} ->
          do_body = extract_do_value(body)
          {norm_args, norm_guards, norm_body} = normalize_clause(args, guard_parts, do_body)
          attr_refs = referenced_attr_versions([args, guard_parts, do_body], attr_versions)
          sig = {name, length(args), norm_args, norm_guards, norm_body, attr_refs}
          {:ok, sig, name, length(args)}

        nil ->
          :error
      end
    end
  end

  defp clause_signature(_, _), do: :error

  defp head_parts({:when, _, [{name, _, args} | guard_parts]})
       when is_atom(name) and is_list(args),
       do: {name, args, guard_parts}

  defp head_parts({name, _, args}) when is_atom(name) and is_list(args), do: {name, args, []}
  defp head_parts(_), do: nil

  defp extract_do_value(body) when is_list(body) do
    case Keyword.fetch(body, :do) do
      {:ok, v} ->
        v

      :error ->
        Enum.find_value(body, fn
          {{:__block__, _, [:do]}, v} -> v
          _ -> nil
        end)
    end
  end

  defp extract_do_value(_), do: nil

  # Normalize args, guards and body together with ONE shared variable-binding map
  # so variable identity is preserved across all three.
  defp normalize_clause(args, guard_parts, do_body) do
    {norm_args, state} = Enum.map_reduce(args, {%{}, 0}, &normalize_node/2)
    {norm_guards, state} = Enum.map_reduce(guard_parts, state, &normalize_node/2)
    {norm_body, _state} = normalize_node(do_body, state)
    {norm_args, norm_guards, norm_body}
  end

  # For every module attribute *used* anywhere in `asts`, its current version
  # (how many times it has been (re)assigned so far in the block). Sorted so the
  # signature is order-independent.
  defp referenced_attr_versions(asts, attr_versions) do
    {_ast, used} =
      Macro.prewalk(asts, MapSet.new(), fn
        {:@, _, [{name, _, ctx}]} = node, acc when is_atom(name) and is_atom(ctx) ->
          {node, MapSet.put(acc, name)}

        node, acc ->
          {node, acc}
      end)

    used
    |> Enum.map(fn name -> {name, Map.get(attr_versions, name, 0)} end)
    |> Enum.sort()
  end

  defp contains_unquote?(head) do
    {_node, found?} =
      Macro.prewalk(head, false, fn
        {form, _, _} = node, _acc when form in [:unquote, :unquote_splicing] -> {node, true}
        node, acc -> {node, acc}
      end)

    found?
  end

  # The Nth distinct variable name becomes `{:v, N}` and a *repeated* name reuses
  # its placeholder, threading `{name => placeholder_index, next_index}`. This
  # keeps `def f(x, x)` (a non-linear equality constraint) distinct from
  # `def f(a, b)`.

  # Bare `_` is always a fresh placeholder (each underscore is independent).
  defp normalize_node({:_, _, ctx}, {names, n}) when is_atom(ctx) do
    {{:v, n}, {names, n + 1}}
  end

  # `__MODULE__` is the current-module constant, NOT a bindable variable. In
  # struct-name position `%__MODULE__{}` matches only this module's struct while
  # `%_{}` matches any struct, so they must stay distinct — keep `__MODULE__`
  # literal rather than collapsing it to a `_`-style placeholder.
  defp normalize_node({:__MODULE__, _, ctx}, state) when is_atom(ctx) do
    {{:special, :__MODULE__}, state}
  end

  # A bare name on the RHS of a pipe (`text |> is_list`) is a FUNCTION reference,
  # not a variable — keep its name literal so `|> is_list` and `|> is_binary`
  # (and other pipe-form guards) stay distinct instead of collapsing to the same
  # placeholder.
  defp normalize_node({:|>, _, [left, {fname, _, ctx}]}, state)
       when is_atom(fname) and is_atom(ctx) do
    {nleft, state} = normalize_node(left, state)
    {{:|>, [nleft, {:fn_ref, fname}]}, state}
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
