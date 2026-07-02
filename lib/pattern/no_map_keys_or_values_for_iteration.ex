defmodule Credence.Pattern.NoMapKeysOrValuesForIteration do
  @moduledoc """
  Performance rule: Detects `Map.values(map)` or `Map.keys(map)` passed
  directly into an `Enum` function, which creates an unnecessary intermediate
  list.

  All `Enum` functions accept maps directly and iterate over `{key, value}`
  pairs without allocating an intermediate list.

  ## Scope — only order-INDEPENDENT terminals are rewritten

  `Map.keys/1` and `Map.values/1` iterate in a different order than a direct
  `Enum`-over-map traversal once the map has more than 32 keys (small-map array
  vs. hash-tree iterator). So the rule rewrites ONLY operations whose result is
  independent of iteration order — `all?`, `any?`, `count`, `empty?`,
  `frequencies`, `frequencies_by`. Order-dependent ops (`map`, `filter`, `find`,
  `at`, `take`, `join`, `reduce`, `sort`, …) would reorder the result and are
  left untouched: neither flagged nor rewritten (check and fix share one scope
  gate, `fixable?/2`). `Enum.sum`/`product`/`max`/`min` are already idiomatic and
  also not flagged.

  ## Automatic fixing

      # Callback wrapping binds the user's variable to the right slot:
      Enum.all?(Map.values(degrees), fn v -> v == 0 end)
      → Enum.all?(degrees, fn {_k, v} -> v == 0 end)

      Map.values(m) |> Enum.count()
      → Enum.count(m)

      Enum.frequencies(Map.keys(m))
      → Enum.frequencies_by(m, fn {k, _} -> k end)

  ## Bad
      Enum.all?(Map.values(degrees), fn v -> v == 0 end)
      Map.values(map) |> Enum.count()
  ## Good
      Enum.all?(degrees, fn {_k, v} -> v == 0 end)
      Enum.count(map)
      Map.values(map) |> Enum.sum()       # already idiomatic
      Map.values(m) |> Enum.filter(...)   # order-dependent — left alone

  ## Glossary (terms used throughout this module)

  - `map_fn`  : the `Map` function being eliminated, either `:keys` or
                `:values`. Drives every `{k, v}` slot decision.
  - `enum_fn` : the `Enum` function the user is calling on the result of
                `Map.keys/values`.
  - `map_expr`: the AST of the actual map being iterated (the argument
                to `Map.keys/values`).
  - `enum_args` / `enum_args`: the *remaining* args of the `Enum` call
                (everything after `Map.keys/values(map)`).
  - "kv pattern" : the destructuring tuple pattern (`{k, _v}` or
                `{_k, v}`) we substitute for the user's single-arg
                callback parameter.
  - "extractor": the closing `Enum.map(..., fn {k, _} -> k end)` we
                append when the inner Enum function returns a list of
                `{k, v}` pairs but the caller only wanted keys/values.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @map_funcs [:keys, :values]

  # Only ORDER-INDEPENDENT terminals are safe to rewrite. `Map.keys/1` and
  # `Map.values/1` iterate in a different order than a direct `Enum`-over-map
  # traversal once the map has > 32 keys (the small-map array vs the hash-tree
  # iterator), so any order-dependent op (`map`, `flat_map`, `reduce`, `find`,
  # `at`, `take`, `join`, `group_by`, `each`'s effect order, …) — and the
  # non-deterministic `random`/`sample`/`shuffle` — would diverge. Only ops whose
  # result is independent of iteration order are rewritten.
  @fixable_funcs ~w(all? any? count empty? frequencies frequencies_by)a

  # ════════════════════════════════════════════════════════════════
  # check
  # ════════════════════════════════════════════════════════════════

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Nested:  Enum.<enum_fn>(Map.<map_fn>(m), ...)
        {{:., _, [{:__aliases__, _, [:Enum]}, enum_fn]}, meta,
         [{{:., _, [{:__aliases__, _, [:Map]}, map_fn]}, _, _} | rest]} = node,
        issues
        when map_fn in @map_funcs ->
          if fixable?(enum_fn, rest),
            do: {node, [issue(map_fn, enum_fn, meta) | issues]},
            else: {node, issues}

        # Piped:  Map.<map_fn>(m) |> Enum.<enum_fn>(...)
        {:|>, meta,
         [
           {{:., _, [{:__aliases__, _, [:Map]}, map_fn]}, _, _},
           {{:., _, [{:__aliases__, _, [:Enum]}, enum_fn]}, _, rest}
         ]} = node,
        issues
        when map_fn in @map_funcs ->
          if fixable?(enum_fn, rest),
            do: {node, [issue(map_fn, enum_fn, meta) | issues]},
            else: {node, issues}

        # Triple-piped:  map |> Map.<map_fn>() |> Enum.<enum_fn>(...)
        {:|>, meta,
         [
           {:|>, _, [_, {{:., _, [{:__aliases__, _, [:Map]}, map_fn]}, _, _}]},
           {{:., _, [{:__aliases__, _, [:Enum]}, enum_fn]}, _, rest}
         ]} = node,
        issues
        when map_fn in @map_funcs ->
          if fixable?(enum_fn, rest),
            do: {node, [issue(map_fn, enum_fn, meta) | issues]},
            else: {node, issues}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  # ════════════════════════════════════════════════════════════════
  # fix
  # ════════════════════════════════════════════════════════════════

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)

    Credence.RuleHelpers.patches_from_ast_transform(ast, source, fn input ->
      transform_ast(input)
    end)
  end

  defp transform_ast(ast) do
    Macro.postwalk(ast, fn
      # Pattern 1 — nested:  Enum.<enum_fn>(Map.<map_fn>(m), rest_args...)
      {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, enum_fn]}, call_meta, args} = node ->
        case args do
          [{{:., _, [{:__aliases__, _, [:Map]}, map_fn]}, _, [map_expr]} | enum_args]
          when map_fn in @map_funcs ->
            # `fixable?` (NOT just `safe_callbacks?`) so the fix rewrites EXACTLY
            # the order-independent `enum_fn`s the check flags — never the
            # order-dependent ones it deliberately skips.
            if fixable?(enum_fn, enum_args) do
              pick(
                fix_nested(enum_fn, dot_meta, alias_meta, call_meta, map_fn, map_expr, enum_args),
                node
              )
            else
              node
            end

          _ ->
            node
        end

      # Pattern 2 — pipe:  Map.<map_fn>(m) |> Enum.<enum_fn>(...)
      {:|>, pipe_meta,
       [
         {{:., _, [{:__aliases__, _, [:Map]}, map_fn]}, _, [map_expr]},
         {{:., _, [{:__aliases__, _, [:Enum]}, enum_fn]}, _, enum_args}
       ]} = node
      when map_fn in @map_funcs ->
        if fixable?(enum_fn, enum_args),
          do: pick(fix_pipe(enum_fn, pipe_meta, map_fn, map_expr, enum_args), node),
          else: node

      # Pattern 3 — triple pipe:  map |> Map.<map_fn>() |> Enum.<enum_fn>(...)
      {:|>, pipe_meta,
       [
         {:|>, _, [map_expr, {{:., _, [{:__aliases__, _, [:Map]}, map_fn]}, _, _}]},
         {{:., _, [{:__aliases__, _, [:Enum]}, enum_fn]}, _, enum_args}
       ]} = node
      when map_fn in @map_funcs ->
        if fixable?(enum_fn, enum_args),
          do: pick(fix_pipe(enum_fn, pipe_meta, map_fn, map_expr, enum_args), node),
          else: node

      node ->
        node
    end)
  end

  # ════════════════════════════════════════════════════════════════
  # fix_nested — rewrites `Enum.<enum_fn>(Map.<map_fn>(m), ...)`
  # ════════════════════════════════════════════════════════════════

  defp fix_nested(enum_fn, dot_meta, alias_meta, call_meta, map_fn, map_expr, enum_args) do
    # Builds `Enum.<fn>(args)` preserving the original call site's
    # metadata, so Sourceror's byte-level patches line up correctly.
    enum = &enum_call_with_meta(dot_meta, alias_meta, call_meta, &1, &2)

    # 1) Wrap any single-arg callbacks in enum_args so the user's
    #    variable binds to the correct slot of the `{k, v}` pair.
    enum_args = wrap_fns(enum_args, map_fn)

    case enum_fn do
      f when f in [:all?, :any?, :frequencies_by] ->
        on_first(enum_args, fn cb -> {:ok, enum.(f, [map_expr, cb])} end)

      :count ->
        case enum_args do
          [] -> {:ok, enum.(:count, [map_expr])}
          [cb | _] -> if function?(cb), do: {:ok, enum.(:count, [map_expr, cb])}, else: :no
        end

      :empty? ->
        {:ok, enum.(:empty?, [map_expr | enum_args])}

      :frequencies ->
        on_empty(enum_args, fn ->
          {:ok, enum.(:frequencies_by, [map_expr, extractor_lambda(map_fn)])}
        end)

      _ ->
        :no
    end
  end

  # ════════════════════════════════════════════════════════════════
  # fix_pipe — rewrites `Map.<map_fn>(m) |> Enum.<enum_fn>(...)`
  # (and the triple-pipe form `map |> Map.<map_fn>() |> Enum.<enum_fn>(...)`)
  # ════════════════════════════════════════════════════════════════

  defp fix_pipe(enum_fn, pipe_meta, map_fn, map_expr, enum_args) do
    # Build the rewritten Enum step. If map_expr is itself already a
    # pipe, append our new Enum call as the next stage; otherwise
    # collapse to a nested call.
    enum = fn fn_name, args ->
      case map_expr do
        {:|>, _, _} -> pipe_into_enum(pipe_meta, map_expr, fn_name, args)
        _ -> enum_call(fn_name, [map_expr | args])
      end
    end

    # 1) Wrap any single-arg callbacks so the user's variable binds
    #    to the correct slot of the `{k, v}` pair.
    enum_args = wrap_fns(enum_args, map_fn)

    case enum_fn do
      f when f in [:all?, :any?, :frequencies_by] ->
        on_first(enum_args, fn cb -> {:ok, enum.(f, [cb])} end)

      :count ->
        case enum_args do
          [] -> {:ok, enum.(:count, [])}
          [cb | _] -> if function?(cb), do: {:ok, enum.(:count, [cb])}, else: :no
        end

      :empty? ->
        {:ok, enum.(:empty?, enum_args)}

      :frequencies ->
        on_empty(enum_args, fn ->
          {:ok, enum.(:frequencies_by, [extractor_lambda(map_fn)])}
        end)

      _ ->
        :no
    end
  end

  # ════════════════════════════════════════════════════════════════
  # callback wrapping
  # ════════════════════════════════════════════════════════════════

  # Walk an Enum call's arg list and rewrite each callback (literal
  # `fn`, `&Mod.func/1`, or a simple `&(... &1 ...)` capture) so its
  # first parameter destructures the `{k, v}` pair that iterating the
  # map directly will yield. Non-callback args are left untouched.
  defp wrap_fns(args, map_fn) do
    Enum.map(args, fn
      {:fn, _, _} = cb ->
        wrap_cb(cb, map_fn)

      {:&, _, [{:/, _, [_, {:__block__, _, [1]}]}]} = cb ->
        wrap_cb(cb, map_fn)

      {:&, _, [_]} = cb ->
        # Complex capture like `&(length(&1) > 1)` — convert it to a
        # `fn` first so we can destructure its head uniformly.
        case capture_to_fn(cb) do
          {:fn, _, _} = converted -> wrap_cb(converted, map_fn)
          _ -> cb
        end

      other ->
        other
    end)
  end

  # `fn p1, ...others -> body`  →  `fn <kv_pattern(p1)>, ...others -> body`
  # Multi-clause lambdas: each clause is rewritten independently.
  defp wrap_cb({:fn, fn_meta, clauses}, map_fn) do
    rewritten =
      Enum.map(clauses, fn {:->, arrow_meta, [head, body]} ->
        {:->, arrow_meta, [destructure_head(head, map_fn), body]}
      end)

    {:fn, fn_meta, rewritten}
  end

  # `&Mod.func/1`  →  `fn {x, _v} -> Mod.func(x) end`  for :keys
  #                →  `fn {_k, x} -> Mod.func(x) end`  for :values
  # Sourceror wraps the arity literal in `:__block__`.
  defp wrap_cb({:&, capture_meta, [{:/, _, [ref, {:__block__, _, [1]}]}]}, map_fn) do
    arg_var = {:x, [], nil}

    {:fn, capture_meta, [{:->, [], [[kv_pattern(arg_var, map_fn)], rebuild_call(ref, arg_var)]}]}
  end

  # `&(expr using &1)`  →  `fn x -> expr end`
  # The resulting `fn` is fed back through `wrap_cb` so the user's
  # captured variable still ends up destructured against the `{k, v}`
  # pair. Multi-arity captures (`&2`, `&3`, ...) are left as-is.
  defp capture_to_fn({:&, capture_meta, [body]}) do
    if uses_higher_capture?(body) do
      {:&, capture_meta, [body]}
    else
      arg_var = {:x, [], nil}

      new_body =
        Macro.prewalk(body, fn
          {:&, _, [1]} -> arg_var
          node -> node
        end)

      {:fn, capture_meta, [{:->, [], [[arg_var], new_body]}]}
    end
  end

  defp uses_higher_capture?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:&, _, [n]} = node, _acc when is_integer(n) and n > 1 -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  # Destructures the first parameter of a lambda clause head, preserving
  # any `when` guard and leaving extra parameters alone (e.g. the `acc`
  # of `Enum.reduce/3`).
  defp destructure_head([{:when, when_meta, [first, guard]} | rest], map_fn) do
    [{:when, when_meta, [kv_pattern(first, map_fn), guard]} | rest]
  end

  defp destructure_head([first | rest], map_fn) do
    [kv_pattern(first, map_fn) | rest]
  end

  defp destructure_head([], _map_fn), do: []

  # Returns the `{k, v}` tuple pattern that binds `user_pattern` to the
  # correct slot of a key-value pair:
  #
  #     :keys    →  {user_pattern, _v}    (user var binds to the KEY)
  #     :values  →  {_k, user_pattern}    (user var binds to the VALUE)
  #
  # Sourceror wraps 2-tuples in `:__block__` to disambiguate them from
  # `{atom, value}` keyword pairs; otherwise `Sourceror.to_string/1`
  # would render the pattern as map-update syntax (`_k => v`).
  defp kv_pattern(user_pattern, :keys),
    do: {:__block__, [], [{user_pattern, {:_v, [], nil}}]}

  defp kv_pattern(user_pattern, :values),
    do: {:__block__, [], [{{:_k, [], nil}, user_pattern}]}

  # `&Mod.func/1`  →  `Mod.func(arg)`   (rebuilds a call from a remote ref)
  # `&local_fn/1`  →  `local_fn(arg)`   (and from a local ref)
  defp rebuild_call({name, _meta, ctx}, arg) when is_atom(ctx) do
    {name, [], [arg]}
  end

  defp rebuild_call({{:., _, [{:__aliases__, _, mod}, func]}, _, []}, arg) do
    {{:., [], [{:__aliases__, [], mod}, func]}, [], [arg]}
  end

  # ════════════════════════════════════════════════════════════════
  # small dispatch helpers
  # ════════════════════════════════════════════════════════════════

  # Apply `fun` to the first arg of `args`; refuse the rewrite if there
  # is no first arg. Used by branches that expect a single callback.
  defp on_first([first | _], fun), do: fun.(first)
  defp on_first(_, _), do: :no

  # Call `fun` only when `args` is empty; refuse the rewrite otherwise.
  # Used by branches that take no callback (e.g. `Enum.max/1`).
  defp on_empty([], fun), do: fun.()
  defp on_empty(_, _), do: :no

  # Pick a rewrite if one was produced, otherwise return the fallback
  # (the original unchanged node).
  defp pick({:ok, node}, _fallback), do: node
  defp pick(:no, fallback), do: fallback

  # Runtime check: is this AST node a `fn ... end` or a `&func/1` capture?
  defp function?({:fn, _, _}), do: true
  defp function?({:&, _, [{:/, _, [_, {:__block__, _, [1]}]}]}), do: true
  defp function?(_), do: false

  # ════════════════════════════════════════════════════════════════
  # AST builders
  # ════════════════════════════════════════════════════════════════

  # `Enum.<fn>(args)` preserving the original call site's metadata.
  defp enum_call_with_meta(dot_meta, alias_meta, call_meta, fn_name, args),
    do: {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, fn_name]}, call_meta, args}

  # `Enum.<fn>(args)` with empty metadata — used for freshly synthesised
  # calls that don't correspond to any node in the input source.
  defp enum_call(fn_name, args),
    do: {{:., [], [{:__aliases__, [], [:Enum]}, fn_name]}, [], args}

  # `lhs |> Enum.<fn>(args)`
  defp pipe_into_enum(pipe_meta, lhs, fn_name, args),
    do: {:|>, pipe_meta, [lhs, enum_call(fn_name, args)]}

  # Sourceror wraps 2-tuples in `:__block__` (so `{a, b}` doesn't get
  # rendered as map-update `a => b`). Builders that mint fresh tuple
  # patterns wrap them for consistency.
  defp wrap_tuple({_a, _b} = pair), do: {:__block__, [], [pair]}

  # The closing `Enum.map(..., <this>)` extractor — projects a list of
  # `{k, v}` pairs back to a list of just-keys or just-values.
  #
  #     :keys    →  fn {k, _} -> k end
  #     :values  →  fn {_, v} -> v end
  defp extractor_lambda(:values),
    do: {:fn, [], [{:->, [], [[wrap_tuple({{:_, [], nil}, {:v, [], nil}})], {:v, [], nil}]}]}

  defp extractor_lambda(:keys),
    do: {:fn, [], [{:->, [], [[wrap_tuple({{:k, [], nil}, {:_, [], nil}})], {:k, [], nil}]}]}

  # ════════════════════════════════════════════════════════════════
  # issue + fixability gate
  # ════════════════════════════════════════════════════════════════

  defp issue(map_fn, enum_fn, meta) do
    %Issue{
      rule: :no_map_keys_or_values_for_iteration,
      message:
        "`Map.#{map_fn}/1` creates an intermediate list before passing to `Enum.#{enum_fn}`. " <>
          "Iterate the map directly — `Enum` functions accept maps and yield `{key, value}` pairs.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  # The single scope gate shared by check AND fix: an `enum_fn` is rewritten iff
  # it is an order-independent terminal (`@fixable_funcs`) whose callbacks are
  # range-safe. The check and the fix call this same predicate, so they flag and
  # rewrite EXACTLY the same set — never an order-dependent op like `filter`.
  defp fixable?(enum_fn, args) do
    enum_fn in @fixable_funcs and safe_callbacks?(args)
  end

  # The rule converts a `&(...)` capture callback to a `fn`, but Sourceror
  # under-reports the source range of a parenthesized `&(...)` whose body ENDS
  # IN A CALL — the range stops at the inner call's `)` and omits the capture's
  # own `)`, so the patch would orphan a paren (`fn … end)`, non-compiling). The
  # conversion is correct; only the patch range is wrong, and only for that
  # shape. So we fire only when every callback is range-safe: a `fn`, a
  # `&foo/1`, or a `&(...)` whose body ends in a literal / variable / capture
  # arg (`&1`) — never a call.
  defp safe_callbacks?(args), do: Enum.all?(args, &safe_callback?/1)

  defp safe_callback?({:&, _, [{:/, _, _}]}), do: true
  defp safe_callback?({:&, _, [body]}), do: ends_in_literal_or_var?(body)
  defp safe_callback?(_), do: true

  @recurse_ops [
    :==,
    :!=,
    :===,
    :!==,
    :<,
    :>,
    :<=,
    :>=,
    :+,
    :-,
    :*,
    :/,
    :and,
    :or,
    :&&,
    :||,
    :++,
    :--,
    :<>,
    :in,
    :|>,
    :..,
    :not,
    :!,
    :|
  ]

  defp ends_in_literal_or_var?({:__block__, _, [inner]}), do: ends_in_literal_or_var?(inner)

  defp ends_in_literal_or_var?({op, _, args}) when op in @recurse_ops and is_list(args),
    do: ends_in_literal_or_var?(List.last(args))

  defp ends_in_literal_or_var?({:&, _, [n]}) when is_integer(n), do: true
  defp ends_in_literal_or_var?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true

  defp ends_in_literal_or_var?(lit)
       when is_integer(lit) or is_float(lit) or is_atom(lit) or is_binary(lit),
       do: true

  defp ends_in_literal_or_var?(_), do: false
end
