defmodule Credence.Pattern.NoMapKeysOrValuesForIteration do
  @moduledoc """
  Performance rule: Detects `Map.values(map)` or `Map.keys(map)` passed
  directly into an `Enum` function, which creates an unnecessary intermediate
  list.

  All `Enum` functions accept maps directly and iterate over `{key, value}`
  pairs without allocating an intermediate list.

  ## Automatic fixing

      # Callback wrapping
      Enum.all?(Map.values(degrees), fn v -> v == 0 end)
      → Enum.all?(degrees, fn {_k, v} -> v == 0 end)

      # find/at → case expression
      Enum.find(Map.values(m), fn v -> v > 0 end)
      → case Enum.find(m, fn {_k, v} -> v > 0 end) do
          nil -> nil; {_, v} -> v
        end

      # filter/sort/etc → chain with Enum.map
      Map.keys(m) |> Enum.filter(fn k -> k > 0 end)
      → m |> Enum.filter(fn {k, _v} -> k > 0 end)
        |> Enum.map(fn {k, _v} -> k end)

  `Enum.sum`, `Enum.product`, `Enum.max`, and `Enum.min` with
  `Map.values`/`Map.keys` are already idiomatic and not flagged.

  ## Bad
      Enum.all?(Map.values(degrees), fn v -> v == 0 end)
      Map.keys(map) |> Enum.map(&to_string/1)
  ## Good
      Enum.all?(degrees, fn {_k, v} -> v == 0 end)
      Enum.map(map, fn {k, _v} -> to_string(k) end)
      Map.values(map) |> Enum.sum()       # already idiomatic
      Enum.max(Map.values(m))              # already idiomatic

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

    ast
    |> Credence.RuleHelpers.patches_from_ast_transform(source, &transform_ast/1)
    |> Enum.map(&correct_capture_range(&1, source))
  end

  # Sourceror's `get_range/1` under-reports the span of a parenthesized
  # `&(...)` capture whose body ends in a nested call (e.g. `&(not blank?(&1))`):
  # the `&` node carries no closing-paren metadata, so the range stops at the
  # inner call's `)` and omits the capture's own wrapping `)`. When we replace
  # such a capture with a `fn`, the diff-based patch is one paren short and
  # orphans that `)` (`fn … end)` — non-compiling output. We recompute the true
  # end by paren-matching the `&(` directly in the source and extend the patch.
  defp correct_capture_range(%{range: %{start: start} = range, change: change} = patch, source)
       when is_binary(change) do
    if String.starts_with?(change, "fn") do
      case capture_paren_end(source, start) do
        nil -> patch
        new_end -> %{patch | range: %{range | end: new_end}}
      end
    else
      patch
    end
  end

  defp correct_capture_range(patch, _source), do: patch

  # If the source at `start` is a parenthesized capture `&(...)`, return the
  # `[line:, column:]` position one past its matching `)`. `nil` for a bare
  # capture (`& &1`, `&foo/1`) — those range correctly and need no correction.
  defp capture_paren_end(source, line: sl, column: sc) do
    chars =
      source
      |> positioned_chars()
      |> Enum.drop_while(fn {_ch, l, c} -> {l, c} < {sl, sc} end)

    case chars do
      [{"&", _, _} | rest] -> scan_to_open_paren(rest)
      _ -> nil
    end
  end

  # Flatten the source into `{grapheme, line, column}` triples (1-based),
  # including a synthetic newline at each line end so positions stay contiguous.
  defp positioned_chars(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {ln, lineno} ->
      line_chars =
        ln
        |> String.graphemes()
        |> Enum.with_index(1)
        |> Enum.map(fn {ch, col} -> {ch, lineno, col} end)

      line_chars ++ [{"\n", lineno, String.length(ln) + 1}]
    end)
  end

  defp scan_to_open_paren([{" ", _, _} | rest]), do: scan_to_open_paren(rest)
  defp scan_to_open_paren([{"(", _, _} | rest]), do: scan_paren(rest, 1)
  defp scan_to_open_paren(_), do: nil

  # Skip string-literal contents so parens inside `"…"` don't unbalance the count.
  defp scan_paren([{"\"", _, _} | rest], depth), do: scan_paren(skip_string(rest), depth)
  defp scan_paren([{"(", _, _} | rest], depth), do: scan_paren(rest, depth + 1)

  defp scan_paren([{")", l, c} | rest], 1) do
    case rest do
      [{_ch, nl, nc} | _] -> [line: nl, column: nc]
      [] -> [line: l, column: c + 1]
    end
  end

  defp scan_paren([{")", _, _} | rest], depth), do: scan_paren(rest, depth - 1)
  defp scan_paren([_ | rest], depth), do: scan_paren(rest, depth)
  defp scan_paren([], _depth), do: nil

  defp skip_string([{"\\", _, _}, _escaped | rest]), do: skip_string(rest)
  defp skip_string([{"\"", _, _} | rest]), do: rest
  defp skip_string([_ | rest]), do: skip_string(rest)
  defp skip_string([]), do: []

  defp transform_ast(ast) do
    Macro.postwalk(ast, fn
      # Pattern 1 — nested:  Enum.<enum_fn>(Map.<map_fn>(m), rest_args...)
      {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, enum_fn]}, call_meta, args} = node ->
        case args do
          [{{:., _, [{:__aliases__, _, [:Map]}, map_fn]}, _, [map_expr]} | enum_args]
          when map_fn in @map_funcs ->
            pick(
              fix_nested(enum_fn, dot_meta, alias_meta, call_meta, map_fn, map_expr, enum_args),
              node
            )

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
        pick(fix_pipe(enum_fn, pipe_meta, map_fn, map_expr, enum_args), node)

      # Pattern 3 — triple pipe:  map |> Map.<map_fn>() |> Enum.<enum_fn>(...)
      {:|>, pipe_meta,
       [
         {:|>, _, [map_expr, {{:., _, [{:__aliases__, _, [:Map]}, map_fn]}, _, _}]},
         {{:., _, [{:__aliases__, _, [:Enum]}, enum_fn]}, _, enum_args}
       ]} = node
      when map_fn in @map_funcs ->
        pick(fix_pipe(enum_fn, pipe_meta, map_fn, map_expr, enum_args), node)

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
      f when f in [:all?, :any?, :each, :map, :flat_map, :frequencies_by, :find_value] ->
        on_first(enum_args, fn cb -> {:ok, enum.(f, [map_expr, cb])} end)

      f when f in [:reduce, :reduce_while] ->
        case enum_args do
          [acc, cb] ->
            if function?(cb), do: {:ok, enum.(f, [map_expr, acc, cb])}, else: :no

          _ ->
            :no
        end

      :count ->
        case enum_args do
          [] -> {:ok, enum.(:count, [map_expr])}
          [cb | _] -> if function?(cb), do: {:ok, enum.(:count, [map_expr, cb])}, else: :no
        end

      f when f in [:max_by, :min_by] ->
        on_first(enum_args, fn cb ->
          {:ok, elem_call(enum.(f, [map_expr, cb]), key_or_value_index(map_fn))}
        end)

      :at ->
        case enum_args do
          [idx] ->
            {:ok, nil_or_extract_case(enum.(:at, [map_expr, idx]), map_fn, nil)}

          [idx, default] ->
            {:ok, nil_or_extract_case(enum.(:at, [map_expr, idx]), map_fn, default)}

          _ ->
            :no
        end

      :find ->
        case enum_args do
          [cb] ->
            if function?(cb),
              do: {:ok, nil_or_extract_case(enum.(:find, [map_expr, cb]), map_fn, nil)},
              else: :no

          [default, cb] ->
            if function?(cb),
              do: {:ok, nil_or_extract_case(enum.(:find, [map_expr, cb]), map_fn, default)},
              else: :no

          _ ->
            :no
        end

      :random ->
        on_empty(enum_args, fn ->
          {:ok, elem_call(enum.(:random, [map_expr]), key_or_value_index(map_fn))}
        end)

      :join ->
        case enum_args do
          [] ->
            {:ok, enum.(:map_join, [map_expr, wrap_str(""), extractor_lambda(map_fn)])}

          [sep] ->
            {:ok, enum.(:map_join, [map_expr, sep, extractor_lambda(map_fn)])}

          _ ->
            :no
        end

      :empty? ->
        {:ok, enum.(:empty?, [map_expr | enum_args])}

      f when f in [:filter, :reject] ->
        on_first(enum_args, fn cb ->
          {:ok, enum.(:map, [enum.(f, [map_expr, cb]), extractor_lambda(map_fn)])}
        end)

      f when f in [:uniq, :dedup] ->
        on_empty(enum_args, fn ->
          by_fn = if f == :uniq, do: :uniq_by, else: :dedup_by

          {:ok,
           enum.(:map, [
             enum.(by_fn, [map_expr, extractor_lambda(map_fn)]),
             extractor_lambda(map_fn)
           ])}
        end)

      f when f in [:uniq_by, :dedup_by] ->
        on_first(enum_args, fn cb ->
          {:ok, enum.(:map, [enum.(f, [map_expr, cb]), extractor_lambda(map_fn)])}
        end)

      f when f in [:take_while, :drop_while] ->
        on_first(enum_args, fn cb ->
          {:ok, enum.(:map, [enum.(f, [map_expr, cb]), extractor_lambda(map_fn)])}
        end)

      f when f in [:take, :drop, :reverse, :sample, :shuffle, :slice, :take_every, :drop_every] ->
        {:ok, enum.(:map, [enum.(f, [map_expr | enum_args]), extractor_lambda(map_fn)])}

      :frequencies ->
        on_empty(enum_args, fn ->
          {:ok, enum.(:frequencies_by, [map_expr, extractor_lambda(map_fn)])}
        end)

      :group_by ->
        case enum_args do
          [key_cb, value_cb] ->
            if function?(key_cb) and function?(value_cb),
              do: {:ok, enum.(:group_by, [map_expr, key_cb, value_cb])},
              else: :no

          _ ->
            :no
        end

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

    # Same shape, but chained off an intermediate `lhs` instead of
    # `map_expr`. Used when the rewrite emits a two-stage pipeline like
    # `m |> Enum.filter(...) |> Enum.map(extractor)`.
    chain = fn lhs, fn_name, args ->
      case lhs do
        {:|>, _, _} -> pipe_into_enum(pipe_meta, lhs, fn_name, args)
        _ -> enum_call(fn_name, [lhs | args])
      end
    end

    # 1) Wrap any single-arg callbacks so the user's variable binds
    #    to the correct slot of the `{k, v}` pair.
    enum_args = wrap_fns(enum_args, map_fn)

    case enum_fn do
      f when f in [:all?, :any?, :each, :map, :flat_map, :frequencies_by, :find_value] ->
        on_first(enum_args, fn cb -> {:ok, enum.(f, [cb])} end)

      f when f in [:reduce, :reduce_while] ->
        case enum_args do
          [acc, cb] -> if function?(cb), do: {:ok, enum.(f, [acc, cb])}, else: :no
          _ -> :no
        end

      :count ->
        case enum_args do
          [] -> {:ok, enum.(:count, [])}
          [cb | _] -> if function?(cb), do: {:ok, enum.(:count, [cb])}, else: :no
        end

      f when f in [:max_by, :min_by] ->
        on_first(enum_args, fn cb ->
          {:ok, pipe_into_elem(pipe_meta, enum.(f, [cb]), key_or_value_index(map_fn))}
        end)

      :at ->
        case enum_args do
          [idx] ->
            {:ok, nil_or_extract_case(enum_call(:at, [map_expr, idx]), map_fn, nil)}

          [idx, default] ->
            {:ok, nil_or_extract_case(enum_call(:at, [map_expr, idx]), map_fn, default)}

          _ ->
            :no
        end

      :find ->
        case enum_args do
          [cb] ->
            if function?(cb),
              do: {:ok, nil_or_extract_case(enum_call(:find, [map_expr, cb]), map_fn, nil)},
              else: :no

          [default, cb] ->
            if function?(cb),
              do: {:ok, nil_or_extract_case(enum_call(:find, [map_expr, cb]), map_fn, default)},
              else: :no

          _ ->
            :no
        end

      :random ->
        on_empty(enum_args, fn ->
          {:ok, pipe_into_elem(pipe_meta, enum.(:random, []), key_or_value_index(map_fn))}
        end)

      :join ->
        case enum_args do
          [] -> {:ok, enum_call(:map_join, [map_expr, wrap_str(""), extractor_lambda(map_fn)])}
          [sep] -> {:ok, enum_call(:map_join, [map_expr, sep, extractor_lambda(map_fn)])}
          _ -> :no
        end

      :empty? ->
        {:ok, enum.(:empty?, enum_args)}

      f when f in [:filter, :reject] ->
        on_first(enum_args, fn cb ->
          {:ok, chain.(enum.(f, [cb]), :map, [extractor_lambda(map_fn)])}
        end)

      f when f in [:uniq, :dedup] ->
        on_empty(enum_args, fn ->
          by_fn = if f == :uniq, do: :uniq_by, else: :dedup_by

          {:ok,
           chain.(
             enum.(by_fn, [extractor_lambda(map_fn)]),
             :map,
             [extractor_lambda(map_fn)]
           )}
        end)

      f when f in [:uniq_by, :dedup_by] ->
        on_first(enum_args, fn cb ->
          {:ok, chain.(enum.(f, [cb]), :map, [extractor_lambda(map_fn)])}
        end)

      f when f in [:take_while, :drop_while] ->
        on_first(enum_args, fn cb ->
          {:ok, chain.(enum.(f, [cb]), :map, [extractor_lambda(map_fn)])}
        end)

      f when f in [:take, :drop, :reverse, :sample, :shuffle, :slice, :take_every, :drop_every] ->
        {:ok, chain.(enum.(f, enum_args), :map, [extractor_lambda(map_fn)])}

      :frequencies ->
        on_empty(enum_args, fn ->
          {:ok, enum.(:frequencies_by, [extractor_lambda(map_fn)])}
        end)

      :group_by ->
        case enum_args do
          [key_cb, value_cb] ->
            if function?(key_cb) and function?(value_cb),
              do: {:ok, enum.(:group_by, [key_cb, value_cb])},
              else: :no

          _ ->
            :no
        end

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

  # `lhs |> elem(index)`
  defp pipe_into_elem(pipe_meta, lhs, index),
    do: {:|>, pipe_meta, [lhs, {:elem, [], [index]}]}

  # `elem(tuple, index)`
  defp elem_call(tuple, index), do: {:elem, [], [tuple, index]}

  # Index into the `{k, v}` pair to read after `max_by` / `min_by` /
  # `random` — 0 picks the key, 1 picks the value.
  defp key_or_value_index(:values), do: wrap_int(1)
  defp key_or_value_index(:keys), do: wrap_int(0)

  # Sourceror's renderer expects literals wrapped in `:__block__` with
  # source-representation metadata. Builders that mint fresh literals
  # wrap them so the surrounding Sourceror-shaped AST stays consistent
  # for `Sourceror.to_string/1`.
  defp wrap_int(n) when is_integer(n),
    do: {:__block__, [token: Integer.to_string(n)], [n]}

  defp wrap_str(s) when is_binary(s),
    do: {:__block__, [delimiter: ~s(")], [s]}

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

  # The destructuring tuple pattern used inside a case clause when we
  # need to extract just-keys / just-values after `find` / `at`.
  #
  #     :keys    →  {k, _v}
  #     :values  →  {_k, v}
  defp extractor_pattern(:values), do: wrap_tuple({{:_k, [], nil}, {:v, [], nil}})
  defp extractor_pattern(:keys), do: wrap_tuple({{:k, [], nil}, {:_v, [], nil}})

  # The bare variable that pairs with `extractor_pattern/1` — the right
  # hand side of the matching clause is just this variable.
  defp extractor_var(:values), do: {:v, [], nil}
  defp extractor_var(:keys), do: {:k, [], nil}

  # Wraps an `Enum.find` / `Enum.at` result in:
  #
  #     case <inner> do
  #       nil -> <default>
  #       {k, v} -> <k or v>
  #     end
  #
  # so the rewritten expression yields just-key / just-value (or the
  # default on miss), matching what the user originally asked for.
  defp nil_or_extract_case(inner, map_fn, default) do
    {:case, [],
     [
       inner,
       [
         do: [
           {:->, [], [[nil], default]},
           {:->, [], [[extractor_pattern(map_fn)], extractor_var(map_fn)]}
         ]
       ]
     ]}
  end

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

  defp fixable?(enum_fn, args) do
    enum_fn in @fixable_funcs and not (enum_fn == :group_by and length(args) < 2)
  end
end
