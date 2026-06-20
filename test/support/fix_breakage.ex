defmodule Credence.Corpus.FixBreakage do
  @moduledoc """
  Dependency-free structural detectors for *broken* corpus fixes — fixes that
  parse (so they clear `apply_rule_fix`'s parse-gate) yet would not COMPILE, or
  silently change behaviour.

  Corpus files cannot be compiled standalone (they reference their own deps and
  sibling modules), so a real `Code.compile_string` raises on unrelated missing
  modules for both the original and the fixed source — masking the bug. Instead
  each detector inspects the FIXED AST (diffed against the original where needed)
  for a specific breakage signature that needs no dependency resolution:

    * `:mangled_attr`  — the fix introduced a read of an `@_underscored` module
      attribute the original never read. Undefined attrs evaluate to `nil`, so a
      head pattern-matching on one silently stops matching. (e.g. a `prefer_*`
      param-underscoring pass walking into `@attr` nodes in a clause head.)

    * `:bad_arity`     — the fix introduced a call to a known stdlib
      `Mod.fun/arity` that does not exist (arity counted AFTER expanding pipes,
      since `x |> Map.new(f)` is `Map.new/2`). Catches a rule that lifts a piped
      collection into an extra argument, e.g. producing `Map.new/3`.

    * `:unsubstituted_equality_guard` — the fix dropped an EQUALITY guard
      (`when var == lit`) from a clause while leaving its head pattern unchanged,
      so the literal was neither moved into the pattern nor kept as a guard. The
      clause now matches a strict superset and shadows its later same-name/arity
      siblings. (A rule that narrows the pattern to compensate — `when x == :a`
      -> `:a` head — has a different pattern string and is correctly NOT flagged;
      a dropped NON-equality guard like `is_list/1` is not flagged either, since
      whether it was truly redundant depends on the other clauses' bodies.)

    * `:bad_defguard` — the fix produced a `defguard(p)` whose head name is not a
      bare, non-operator atom call (e.g. `defguardp is_integer(x) and x > 0`).

    * `:deleted_dynamic_clause` — the fix deleted a clause whose head name is
      DYNAMIC (`unquote(...)`). Reachability of macro-generated clauses can't be
      proven structurally, so deleting one as an "unreachable duplicate" can drop
      a live clause whose body is still invoked.

  `check/2` applies a rule's fix to a corpus file and returns `[{kind, detail}]`
  for every signature tripped (`[]` when the fix is clean or a no-op).
  """

  alias Credence.{RuleHelpers, RuleName}

  @stdlib ~w(Map Enum Keyword List String Tuple MapSet Kernel)a

  @doc "Apply `rule`'s fix to corpus file `rel` and return any breakage signatures."
  @spec check(String.t(), String.t()) :: [{atom(), term()}]
  def check(rule, rel) do
    src = File.read!(Path.join(Credence.Corpus.root(), rel))
    fixed = safe_fix(rule, src)

    if fixed == src do
      []
    else
      with o when not is_nil(o) <- quoted(src),
           f when not is_nil(f) <- quoted(fixed) do
        []
        |> add(:mangled_attr, mangled_attr(o, f))
        |> add(:bad_arity, bad_arity(o, f))
        |> add(:unsubstituted_equality_guard, unsubstituted_equality_guard(o, f))
        |> add(:bad_defguard, bad_defguard(o, f))
        |> add(:deleted_dynamic_clause, deleted_dynamic_clause(o, f))
      else
        _ -> []
      end
    end
  end

  defp safe_fix(rule, src) do
    module = RuleName.derive(to_string(rule), :pattern).rule_module
    RuleHelpers.apply_rule_fix(module, src)
  rescue
    _ -> src
  end

  defp add(acc, _kind, []), do: acc
  defp add(acc, kind, found), do: acc ++ [{kind, found}]

  defp quoted(src) do
    {res, _} = Code.with_diagnostics(fn -> Code.string_to_quoted(src) end)

    case res do
      {:ok, ast} -> ast
      _ -> nil
    end
  end

  # ── :mangled_attr ─────────────────────────────────────────────────────────
  defp attr_reads(ast) do
    {_, acc} =
      Macro.prewalk(ast, [], fn
        {:@, _, [{name, _, ctx}]} = node, acc
        when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) ->
          {node, [name | acc]}

        node, acc ->
          {node, acc}
      end)

    MapSet.new(acc)
  end

  defp mangled_attr(orig, fixed) do
    MapSet.difference(attr_reads(fixed), attr_reads(orig))
    |> Enum.filter(&String.starts_with?(Atom.to_string(&1), "_"))
  end

  # ── :bad_arity ────────────────────────────────────────────────────────────
  # `a |> Mod.fun(b)` runs as Mod.fun/2 though the raw call has arity 1; expand
  # pipes so arity counts reflect what actually runs.
  defp expand_pipes(ast) do
    Macro.postwalk(ast, fn
      {:|>, _, [l, {c, m, args}]} when is_list(args) -> {c, m, [l | args]}
      other -> other
    end)
  end

  # `&Mod.fun/n` is a reference whose inner `Mod.fun()` carries an empty arg list
  # — not a 0-arity call. Strip captures before counting.
  defp strip_captures(ast) do
    Macro.prewalk(ast, fn
      {:&, _, _} -> :__capture__
      other -> other
    end)
  end

  defp stdlib_calls(ast) do
    {_, acc} =
      Macro.prewalk(ast |> strip_captures() |> expand_pipes(), [], fn
        {{:., _, [{:__aliases__, _, [mod]}, fun]}, _, args} = node, acc
        when mod in @stdlib and is_atom(fun) and is_list(args) ->
          {node, [{mod, fun, length(args)} | acc]}

        node, acc ->
          {node, acc}
      end)

    MapSet.new(acc)
  end

  defp bad_arity(orig, fixed) do
    new = MapSet.difference(stdlib_calls(fixed), stdlib_calls(orig))

    for {mod, fun, ar} <- new,
        m = Module.concat(Elixir, mod),
        Code.ensure_loaded?(m),
        not function_exported?(m, fun, ar) and not macro_exported?(m, fun, ar),
        do: {mod, fun, ar}
  end

  # ── clause inventory (shared by shadow / dynamic-clause detectors) ─────────
  defp clauses(ast) do
    {_, acc} =
      Macro.prewalk(ast, [], fn
        {def_kw, _, [head, _body]} = node, acc when def_kw in [:def, :defp] ->
          {node, [clause_info(head) | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(acc)
  end

  # {name_arity, guard_ast_or_nil, pattern_string}
  defp clause_info({:when, _, [call, guard]}), do: {name_arity(call), guard, args_str(call)}
  defp clause_info(call), do: {name_arity(call), nil, args_str(call)}

  defp args_str({_callee, _, args}) when is_list(args), do: Macro.to_string(args)
  defp args_str(_), do: ""

  # head of a clause/call is `{callee, meta, args}`; callee is an atom for a
  # normal name or an AST node (e.g. `{:unquote, _, [..]}`) inside a macro.
  defp name_arity({callee, _, args}) when is_list(args), do: {keyify(callee), length(args)}
  defp name_arity({callee, _, ctx}) when is_atom(ctx) or is_nil(ctx), do: {keyify(callee), 0}
  defp name_arity(other), do: {Macro.to_string(other), :unknown}

  defp keyify(atom) when is_atom(atom), do: atom
  defp keyify(other), do: Macro.to_string(other)

  # ── :unsubstituted_equality_guard ─────────────────────────────────────────
  defp unsubstituted_equality_guard(orig, fixed) do
    groups = fn list ->
      list |> Enum.with_index() |> Enum.group_by(fn {{na, _g, _a}, _i} -> na end)
    end

    go = groups.(clauses(orig))
    gf = groups.(clauses(fixed))

    for {na, fitems} <- gf,
        oitems = Map.get(go, na, []),
        # a guard-drop keeps the clause count (not a clause add/remove)
        length(fitems) == length(oitems) and length(fitems) > 1,
        last_pos = fitems |> Enum.map(fn {_, i} -> i end) |> Enum.max(),
        Enum.zip(fitems, oitems)
        # orig had an EQUALITY guard, fixed dropped it, the pattern is unchanged
        # (literal not moved into the head), and the clause has later siblings.
        |> Enum.any?(fn {{{_, fg, fa}, fi}, {{_, og, oa}, _}} ->
          is_nil(fg) and equality_guard?(og) and fa == oa and fi < last_pos
        end),
        reduce: [] do
      acc -> [na | acc]
    end
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp equality_guard?(nil), do: false

  defp equality_guard?(guard) do
    {_, found?} =
      Macro.prewalk(guard, false, fn
        {op, _, [_, _]} = node, _ when op in [:==, :===] -> {node, true}
        node, acc -> {node, acc}
      end)

    found?
  end

  # ── :bad_defguard ─────────────────────────────────────────────────────────
  defp bad_defguard(orig, fixed) do
    bad = fn ast ->
      {_, acc} =
        Macro.prewalk(ast, [], fn
          {dg, _, [head | _]} = node, acc when dg in [:defguard, :defguardp] ->
            name =
              case head do
                {:when, _, [call, _]} -> call
                call -> call
              end

            ok =
              case name do
                {n, _, a} when is_atom(n) and is_list(a) -> not Macro.operator?(n, length(a))
                {n, _, a} when is_atom(n) and (is_atom(a) or is_nil(a)) -> true
                _ -> false
              end

            {node, if(ok, do: acc, else: [Macro.to_string(name) | acc])}

          node, acc ->
            {node, acc}
        end)

      MapSet.new(acc)
    end

    MapSet.difference(bad.(fixed), bad.(orig)) |> Enum.sort()
  end

  # ── :deleted_dynamic_clause ───────────────────────────────────────────────
  defp deleted_dynamic_clause(orig, fixed) do
    dyn = fn ast ->
      clauses(ast)
      |> Enum.map(&elem(&1, 0))
      |> Enum.reject(fn {k, _} -> is_atom(k) end)
      |> Enum.frequencies()
    end

    fo = dyn.(orig)
    ff = dyn.(fixed)

    for {k, n} <- fo, Map.get(ff, k, 0) < n, do: k
  end
end
