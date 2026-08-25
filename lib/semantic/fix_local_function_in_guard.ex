defmodule Credence.Semantic.FixLocalFunctionInGuard do
  @moduledoc """
  Fixes the compile error caused by calling a local function inside a guard.

  LLMs define a helper like `defp is_range(x), do: is_map(x)` and then use it in
  a guard (`when is_range(x)`). The compiler rejects it — only macros can be
  invoked inside a guard:

      "cannot find or invoke local is_range/1 inside a guard. Only macros can
       be invoked inside a guard and they must be defined before their
       invocation. Called as: is_range(length_range)"

  The fix **inlines the helper** into the guard, substituting the call's
  arguments for the helper's parameters.

  ## When it inlines, and when it declines

  Inlining is only sound when the helper's body is something a guard can
  actually contain, so all of these must hold:

    * exactly **one** `def/defp` clause for that name and arity, unguarded;
    * its parameters are distinct plain variables (no patterns, no defaults);
    * its body is a **single expression** built only from those parameters,
      literals, and calls that are legal in a guard (`@guard_safe`).

  Anything else no-ops — a helper with several clauses, a pattern in the head,
  or a body calling something guards forbid. `is_blank(l)` defined as
  `byte_size(String.trim(l)) == 0` is the instructive case: it *looks*
  inlinable, but `String.trim/1` is not allowed in a guard, so inlining it
  would replace one compile error with another. That is left for a human
  (escalation ledger row 115).

  ## Ordering against `NoHallucinatedGuardFn`

  Both rules claim `cannot find or invoke local <name>/<arity> inside a guard`,
  and they split the case cleanly: if the module really defines that helper, the
  repair is to inline it (this rule); if nothing defines it, it was hallucinated
  and the repair is `NoHallucinatedGuardFn`'s.

  This rule therefore runs **490**, before the 500 default. It looks for a real
  definition, and where there is none it declines — and `lib/semantic.ex` hands
  the diagnostic to the next matching rule. Widening the matcher without that
  ordering is what made the two contend on nothing but their module names
  (docs/22 T1.2's gate caught exactly that).

  ## It declines out loud

  `should_report?/2` reports only when `fix/2` would really rewrite. Semantic
  dispatch is first-match-wins, so a rule that matches and then no-ops consumes
  the diagnostic and starves whatever else could have handled it — which is
  exactly what happened to `NoHallucinatedGuardFn` on `when is_range(r)` with no
  local `is_range` defined at all (ledger row 196).

  ## Bad

      defmodule LocalFnInGuardFLFIG do
        defp is_range(x), do: is_map(x)

        def convert(x) when is_range(x), do: x
        def describe(x), do: is_range(x)
      end

  ## Good

      defmodule LocalFnInGuardFLFIG do
        defp is_range(x), do: is_map(x)

        def convert(x) when is_map(x), do: x
        def describe(x), do: is_range(x)
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  # Inline a REAL local before `NoHallucinatedGuardFn` (500) treats the name as
  # hallucinated — see "## Ordering" above.
  @impl true
  def priority, do: 490

  # Any local, any arity. This was pinned to the literal string
  # `"cannot find or invoke local is_range/1 inside a guard"` — one name, one
  # arity — so `is_blank/1`, `table/0` and `__match_pattern__/2` all produced
  # `no rule matched diagnostic` (escalation ledger rows 115, 145, 192). The
  # rule's NAME promised a general repair its matcher never attempted.
  @match_re ~r/cannot find or invoke local (?<name>[a-zA-Z_][a-zA-Z0-9_?!]*)\/(?<arity>\d+) inside a guard/

  # Calls a guard may legally contain. Inlining a body that steps outside this
  # replaces one compile error with another, so it is the whole safety
  # condition: conservative on purpose, and easy to widen with evidence.
  @guard_safe ~w(
    is_atom is_binary is_bitstring is_boolean is_float is_function is_integer
    is_list is_map is_map_key is_nil is_number is_pid is_port is_reference
    is_struct is_tuple is_exception
    abs binary_part bit_size byte_size ceil div elem floor hd length map_size
    node rem round self tl trunc tuple_size not and or in
    == != === !== > >= < <= + - * /
  )a

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    Regex.match?(@match_re, msg)
  end

  def match?(_), do: false

  @doc """
  Report only when `fix/2` would really rewrite (ledger row 196).

  The guard IS the fix, so the two cannot disagree about what this rule can do.
  """
  @spec should_report?(map(), String.t()) :: boolean()
  def should_report?(diagnostic, source), do: fix(source, diagnostic) != source

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_local_function_in_guard,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    with %{"name" => name, "arity" => arity} <-
           Regex.named_captures(@match_re, diagnostic.message),
         {:ok, ast} <- Sourceror.parse_string(source),
         target = {String.to_atom(name), String.to_integer(arity)},
         {:ok, module} <- diagnosed_module(ast, line(diagnostic)),
         {:ok, module_body} <- module_body(module),
         {:ok, params, body} <- inlinable_helper(module_body, target) do
      {new_body, changed} = inline_in_guards(module_body, target, params, body)
      new_ast = replace_node(ast, module_body, new_body)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # `{:ok, params, body}` when exactly one unguarded clause defines `target`,
  # its parameters are distinct plain variables, and its body is a single
  # guard-safe expression over them.
  defp inlinable_helper(ast, {name, arity} = target) do
    local_signatures = ast |> local_defs() |> Enum.map(&def_head/1) |> MapSet.new()

    with [{kind, _, [call, body_kw]}] <- local_defs(ast, target),
         true <- kind in [:def, :defp],
         {^name, _, raw_args} <- call,
         args = List.wrap(raw_args),
         true <- length(args) == arity,
         {:ok, params} <- plain_params(args),
         {:ok, body} <- body_of(body_kw),
         body = unwrap_block(body),
         true <- guard_safe?(body, params, local_signatures) do
      {:ok, params, body}
    else
      _ -> :error
    end
  end

  # Every parameter must be a distinct bare variable. A pattern (`%{}`, `[h|t]`)
  # or a default (`\\`) cannot be substituted by name.
  defp plain_params(args) do
    names =
      Enum.map(args, fn
        {n, _, ctx} when is_atom(n) and is_atom(ctx) -> n
        _ -> nil
      end)

    cond do
      Enum.any?(names, &is_nil/1) -> :error
      length(Enum.uniq(names)) != length(names) -> :error
      true -> {:ok, names}
    end
  end

  # A zero-arity call in guard position is `{name, meta, []}` after Sourceror
  # parses `table()`, but `{name, meta, nil}` when written bare. Both are the
  # same call.
  defp guard_call_args(args) when is_list(args), do: args
  defp guard_call_args(ctx) when is_atom(ctx), do: []

  # Only the helper's own parameters, literals, and calls a guard permits.
  defp guard_safe?({:__block__, _, [literal]}, _params, _locals) when not is_tuple(literal),
    do: true

  defp guard_safe?(literal, _params, _locals)
       when is_atom(literal) or is_number(literal),
       do: true

  defp guard_safe?({var, _, ctx}, params, _locals) when is_atom(var) and is_atom(ctx),
    do: var in params

  defp guard_safe?({op, _, args}, params, locals) when is_atom(op) and is_list(args),
    do:
      op in @guard_safe and
        not MapSet.member?(locals, {op, length(args)}) and
        Enum.all?(args, &guard_safe?(&1, params, locals))

  defp guard_safe?(_node, _params, _locals), do: false

  # Replace every guard-position call to `target` with the helper's body, its
  # parameters substituted by that call's arguments.
  defp inline_in_guards(ast, target, params, body) do
    map_scope(ast, false, fn
      {:when, when_meta, [fn_head, guard]}, acc ->
        {new_guard, changed} = inline_call(guard, target, params, body)
        {{:when, when_meta, [fn_head, new_guard]}, acc || changed}

      node, acc ->
        {node, acc}
    end)
  end

  defp inline_call({name, meta, raw_args}, {name, arity}, params, body)
       when is_list(raw_args) or is_atom(raw_args) do
    args = guard_call_args(raw_args)

    if length(args) == arity do
      {body |> substitute(Enum.zip(params, args)) |> reposition(meta), true}
    else
      {{name, meta, raw_args}, false}
    end
  end

  defp inline_call({op, meta, args}, target, params, body) when is_list(args) do
    {new_args, changed} =
      Enum.map_reduce(args, false, fn arg, acc ->
        {new_arg, arg_changed} = inline_call(arg, target, params, body)
        {new_arg, acc || arg_changed}
      end)

    {{op, meta, new_args}, changed}
  end

  defp inline_call(node, _target, _params, _body), do: {node, false}

  # The inlined body comes from the helper's definition and carries ITS line and
  # column. Splicing that into a guard tells Sourceror the node lives elsewhere,
  # and it re-renders the whole clause — turning `def f(x) when g(x), do: x` into
  # a wrapped two-line form. Only the bytes the rule means to change should move,
  # so the body adopts the call site's position and drops its own.
  defp reposition(node, call_meta) do
    Macro.prewalk(node, fn
      {form, meta, args} when is_list(meta) ->
        {form, Keyword.drop(meta, [:line, :column, :end_of_expression, :newlines]), args}

      other ->
        other
    end)
    |> case do
      {form, meta, args} when is_list(meta) -> {form, Keyword.merge(meta, call_meta), args}
      other -> other
    end
  end

  defp substitute(body, bindings) do
    Macro.prewalk(body, fn
      {var, _meta, ctx} = node when is_atom(var) and is_atom(ctx) ->
        case List.keyfind(bindings, var, 0) do
          {^var, replacement} -> replacement
          nil -> node
        end

      node ->
        node
    end)
  end

  # Every def/defp clause for `target`, guarded heads included — more than one
  # clause (or a guarded one) fails the shape check above.
  defp local_defs(ast, target), do: Enum.filter(local_defs(ast), &(def_head(&1) == target))

  defp local_defs(ast) do
    {_, defs} =
      map_scope(ast, [], fn
        {kind, _, [_ | _]} = node, acc when kind in [:def, :defp] -> {node, [node | acc]}
        node, acc -> {node, acc}
      end)

    Enum.reverse(defs)
  end

  # Walk executable source in one module, but never generated code or a nested
  # module, where names resolve in a different lexical scope.
  defp map_scope({form, _, _} = node, acc, _fun) when form in [:quote, :defmodule],
    do: {node, acc}

  defp map_scope(node, acc, fun) do
    {node, acc} = fun.(node, acc)

    case node do
      {form, meta, args} when is_list(args) ->
        {args, acc} = Enum.map_reduce(args, acc, &map_scope(&1, &2, fun))
        {{form, meta, args}, acc}

      list when is_list(list) ->
        Enum.map_reduce(list, acc, &map_scope(&1, &2, fun))

      tuple when is_tuple(tuple) ->
        {items, acc} = tuple |> Tuple.to_list() |> Enum.map_reduce(acc, &map_scope(&1, &2, fun))
        {List.to_tuple(items), acc}

      other ->
        {other, acc}
    end
  end

  defp diagnosed_module(ast, diagnostic_line) do
    modules = collect_modules(ast)

    modules
    |> Enum.filter(fn {:defmodule, meta, _} ->
      start_line = Keyword.get(meta, :line, 0)
      end_line = meta |> Keyword.get(:end, []) |> Keyword.get(:line, start_line)
      diagnostic_line >= start_line and diagnostic_line <= end_line
    end)
    |> Enum.min_by(
      fn {:defmodule, meta, _} ->
        Keyword.get(Keyword.get(meta, :end, []), :line, 0) - Keyword.get(meta, :line, 0)
      end,
      fn -> nil end
    )
    |> case do
      nil -> if length(modules) == 1, do: {:ok, hd(modules)}, else: :error
      module -> {:ok, module}
    end
  end

  defp collect_modules({:quote, _, _}), do: []

  defp collect_modules({:defmodule, _, args} = module) do
    [module | Enum.flat_map(args, &collect_modules/1)]
  end

  defp collect_modules({_, _, args}) when is_list(args),
    do: Enum.flat_map(args, &collect_modules/1)

  defp collect_modules(list) when is_list(list), do: Enum.flat_map(list, &collect_modules/1)

  defp collect_modules(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.flat_map(&collect_modules/1)

  defp collect_modules(_), do: []

  defp module_body({:defmodule, _, [_name, body_kw]}) do
    body_of(body_kw)
  end

  defp replace_node(node, target, replacement) when node == target, do: replacement

  defp replace_node({form, meta, args}, target, replacement) when is_list(args),
    do: {form, meta, Enum.map(args, &replace_node(&1, target, replacement))}

  defp replace_node(list, target, replacement) when is_list(list),
    do: Enum.map(list, &replace_node(&1, target, replacement))

  defp replace_node(tuple, target, replacement) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&replace_node(&1, target, replacement))
    |> List.to_tuple()
  end

  defp replace_node(node, _target, _replacement), do: node

  defp def_head({_kind, _, [{:when, _, [call | _]} | _]}), do: call_name_arity(call)
  defp def_head({_kind, _, [call | _]}), do: call_name_arity(call)

  defp call_name_arity({name, _, args}) when is_atom(name) and is_list(args),
    do: {name, length(args)}

  # `defp table, do: :ok` — a zero-arity head written without parentheses has
  # `nil` args, not `[]`, so it never matched and `table/0` looked undefined
  # (escalation ledger row 145).
  defp call_name_arity({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: {name, 0}

  defp call_name_arity(_), do: nil

  defp body_of([{{:__block__, _, [:do]}, body}]), do: {:ok, body}
  defp body_of([{:do, body}]), do: {:ok, body}
  defp body_of(_), do: :error

  defp unwrap_block({:__block__, _, [single]}) when is_tuple(single), do: single
  defp unwrap_block(node), do: node

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
