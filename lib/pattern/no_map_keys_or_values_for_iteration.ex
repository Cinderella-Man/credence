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

      # max/min → max_by/min_by + elem
      Enum.max(Map.values(m))
      → Enum.max_by(m, fn {_k, v} -> v end) |> elem(1)

      # sum/product → reduce
      Enum.sum(Map.values(m))
      → Enum.reduce(m, 0, fn {_k, v}, acc -> acc + v end)

      # find/at → case expression
      Enum.find(Map.values(m), fn v -> v > 0 end)
      → case Enum.find(m, fn {_k, v} -> v > 0 end) do
          nil -> nil; {_, v} -> v
        end

      # filter/sort/etc → chain with Enum.map
      Map.keys(m) |> Enum.filter(fn k -> k > 0 end)
      → m |> Enum.filter(fn {k, _v} -> k > 0 end)
        |> Enum.map(fn {k, _v} -> k end)

  Functions returning complex structures (`chunk_every`, `zip`, `split`,
  `with_index`, `scan`, `tally`, etc.) cannot be safely auto-fixed and
  are handled by `NoMapKeysOrValuesForRawIteration`.

  ## Bad
      Enum.all?(Map.values(degrees), fn v -> v == 0 end)
      Map.keys(map) |> Enum.map(&to_string/1)
  ## Good
      Enum.all?(degrees, fn {_k, v} -> v == 0 end)
      Enum.map(map, fn {k, _v} -> to_string(k) end)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @map_funcs [:keys, :values]

  @fixable_funcs ~w(
    all? any? count each map flat_map frequencies_by find_value
    reduce reduce_while
    max min max_by min_by
    sum product
    at find random empty?
    join
    filter reject
    sort sort_by
    uniq uniq_by dedup dedup_by
    take drop take_while drop_while
    reverse sample shuffle slice
    frequencies group_by
    take_every drop_every
  )a

  @impl true
  def fixable?, do: true

  # ═══════════════════════════════════════════════════════════════════
  # check
  # ═══════════════════════════════════════════════════════════════════

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Nested: Enum.func(Map.keys/values(m), ...)
        {{:., _, [{:__aliases__, _, [:Enum]}, efunc]}, meta,
         [{{:., _, [{:__aliases__, _, [:Map]}, mfunc]}, _, _} | rest]} = node,
        issues
        when mfunc in @map_funcs ->
          if fixable?(efunc, rest),
            do: {node, [issue(mfunc, efunc, meta) | issues]},
            else: {node, issues}

        # Piped: Map.keys/values(m) |> Enum.func(...)
        {:|>, meta,
         [
           {{:., _, [{:__aliases__, _, [:Map]}, mfunc]}, _, _},
           {{:., _, [{:__aliases__, _, [:Enum]}, efunc]}, _, rest}
         ]} = node,
        issues
        when mfunc in @map_funcs ->
          if fixable?(efunc, rest),
            do: {node, [issue(mfunc, efunc, meta) | issues]},
            else: {node, issues}

        # Triple pipe: map |> Map.keys/values() |> Enum.func(...)
        {:|>, meta,
         [
           {:|>, _, [_, {{:., _, [{:__aliases__, _, [:Map]}, mfunc]}, _, _}]},
           {{:., _, [{:__aliases__, _, [:Enum]}, efunc]}, _, rest}
         ]} = node,
        issues
        when mfunc in @map_funcs ->
          if fixable?(efunc, rest),
            do: {node, [issue(mfunc, efunc, meta) | issues]},
            else: {node, issues}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  # ═══════════════════════════════════════════════════════════════════
  # fix
  # ═══════════════════════════════════════════════════════════════════

  @impl true
  def fix(source, _opts) do
    {:ok, ast} = source |> Code.string_to_quoted(columns: true)

    # Skip the Sourceror.to_string round-trip when nothing was rewritten —
    # it strips heredoc tokens.
    case Macro.postwalk(ast, fn
           # Pattern 1 — nested: Enum.func(Map.keys/values(m), rest_args...)
           {{:., dot, [{:__aliases__, al, [:Enum]}, f]}, cm, args} = node ->
             case args do
               [{{:., _, [{:__aliases__, _, [:Map]}, mfunc]}, _, [ma]} | rest]
               when mfunc in @map_funcs ->
                 pick(fix_nested(f, dot, al, cm, mfunc, ma, rest), node)

               _ ->
                 node
             end

           # Pattern 2 — pipe: Map.keys/values(m) |> Enum.func(...)
           {:|>, pm,
            [
              {{:., _, [{:__aliases__, _, [:Map]}, mfunc]}, _, [ma]},
              {{:., _, [{:__aliases__, _, [:Enum]}, f]}, _, ea}
            ]} = node
           when mfunc in @map_funcs ->
             pick(fix_pipe(f, pm, mfunc, ma, ea), node)

           # Pattern 3 — triple pipe: map |> Map.keys/values() |> Enum.func(...)
           {:|>, pm,
            [
              {:|>, _, [ma, {{:., _, [{:__aliases__, _, [:Map]}, mfunc]}, _, _}]},
              {{:., _, [{:__aliases__, _, [:Enum]}, f]}, _, ea}
            ]} = node
           when mfunc in @map_funcs ->
             pick(fix_pipe(f, pm, mfunc, ma, ea), node)

           node ->
             node
         end) do
      ^ast -> source
      fixed -> Sourceror.to_string(fixed)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # fix_nested — "Enum.func(Map.values(m), rest...)"
  # ═══════════════════════════════════════════════════════════════════

  defp fix_nested(f, dot, al, cm, mfunc, ma, rest) do
    mk = &en(dot, al, cm, &1, &2)

    # 1) Wrap any lambda/capture callbacks in rest
    orig_rest = rest
    rest = wrap_fns(rest)

    # 2) For sort/2 with a lambda sorter, use the original (unwrapped) callback
    #    to avoid double-wrapping — wrap_sort does its own destructuring.
    rest =
      case {f, orig_rest} do
        {:sort, [s]} -> if function?(s), do: [wrap_sort(s, mfunc)], else: rest
        _ -> rest
      end

    case f do
      g when g in [:all?, :any?, :each, :map, :flat_map, :frequencies_by, :find_value] ->
        on_first(rest, fn w -> {:ok, mk.(g, [ma, w])} end)

      g when g in [:reduce, :reduce_while] ->
        case rest do
          [acc, cb] -> if function?(cb), do: {:ok, mk.(g, [ma, acc, cb])}, else: :no
          _ -> :no
        end

      :count ->
        case rest do
          [] -> {:ok, mk.(:count, [ma])}
          [cb | _] -> if function?(cb), do: {:ok, mk.(:count, [ma, cb])}, else: :no
        end

      :max ->
        on_empty(rest, fn -> {:ok, el(mk.(:max_by, [ma, ex(mfunc)]), ei(mfunc))} end)

      :min ->
        on_empty(rest, fn -> {:ok, el(mk.(:min_by, [ma, ex(mfunc)]), ei(mfunc))} end)

      g when g in [:max_by, :min_by] ->
        on_first(rest, fn w -> {:ok, el(mk.(g, [ma, w]), ei(mfunc))} end)

      :sum ->
        on_empty(rest, fn -> {:ok, mk.(:reduce, [ma, 0, rc(mfunc, :+)])} end)

      :product ->
        on_empty(rest, fn -> {:ok, mk.(:reduce, [ma, 1, rc(mfunc, :*)])} end)

      :at ->
        case rest do
          [idx] -> {:ok, nc(mk.(:at, [ma, idx]), mfunc, nil)}
          [idx, default] -> {:ok, nc(mk.(:at, [ma, idx]), mfunc, default)}
          _ -> :no
        end

      :find ->
        case rest do
          [cb] ->
            if function?(cb), do: {:ok, nc(mk.(:find, [ma, cb]), mfunc, nil)}, else: :no

          [default, cb] ->
            if function?(cb), do: {:ok, nc(mk.(:find, [ma, cb]), mfunc, default)}, else: :no

          _ ->
            :no
        end

      :random ->
        on_empty(rest, fn -> {:ok, el(mk.(:random, [ma]), ei(mfunc))} end)

      :join ->
        case rest do
          [] -> {:ok, mk.(:map_join, [ma, "", ex(mfunc)])}
          [sep] -> {:ok, mk.(:map_join, [ma, sep, ex(mfunc)])}
          _ -> :no
        end

      :empty? ->
        {:ok, mk.(:empty?, [ma | rest])}

      g when g in [:filter, :reject] ->
        on_first(rest, fn w -> {:ok, mk.(:map, [mk.(g, [ma, w]), ex(mfunc)])} end)

      :sort ->
        case rest do
          [] ->
            {:ok, mk.(:map, [mk.(:sort_by, [ma, ex(mfunc)]), ex(mfunc)])}

          [s] ->
            cond do
              is_atom(s) ->
                {:ok, mk.(:map, [mk.(:sort_by, [ma, ex(mfunc), s]), ex(mfunc)])}

              function?(s) ->
                {:ok, mk.(:map, [mk.(:sort, [ma, s]), ex(mfunc)])}

              true ->
                :no
            end

          _ ->
            :no
        end

      :sort_by ->
        on_first(rest, fn w ->
          opts = tl(rest)
          {:ok, mk.(:map, [mk.(:sort_by, [ma, w | opts]), ex(mfunc)])}
        end)

      g when g in [:uniq, :dedup] ->
        on_empty(rest, fn ->
          by = if g == :uniq, do: :uniq_by, else: :dedup_by
          {:ok, mk.(:map, [mk.(by, [ma, ex(mfunc)]), ex(mfunc)])}
        end)

      g when g in [:uniq_by, :dedup_by] ->
        on_first(rest, fn w -> {:ok, mk.(:map, [mk.(g, [ma, w]), ex(mfunc)])} end)

      g when g in [:take_while, :drop_while] ->
        on_first(rest, fn w -> {:ok, mk.(:map, [mk.(g, [ma, w]), ex(mfunc)])} end)

      g when g in [:take, :drop, :reverse, :sample, :shuffle, :slice, :take_every, :drop_every] ->
        {:ok, mk.(:map, [mk.(g, [ma | rest]), ex(mfunc)])}

      :frequencies ->
        on_empty(rest, fn -> {:ok, mk.(:frequencies_by, [ma, ex(mfunc)])} end)

      :group_by ->
        case rest do
          [kc, vc] ->
            if function?(kc) and function?(vc), do: {:ok, mk.(:group_by, [ma, kc, vc])}, else: :no

          _ ->
            :no
        end

      _ ->
        :no
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # fix_pipe — "Map.values(m) |> Enum.func(ea)"
  # ═══════════════════════════════════════════════════════════════════

  defp fix_pipe(f, pm, mfunc, ma, ea) do
    # Build Enum call: collapses to nested when ma isn't itself a pipe
    mk = fn func, args ->
      case ma do
        {:|>, _, _} -> pe(pm, ma, func, args)
        _ -> sn(func, [ma | args])
      end
    end

    mk2 = fn lhs, func, args ->
      case lhs do
        {:|>, _, _} -> pe(pm, lhs, func, args)
        _ -> sn(func, [lhs | args])
      end
    end

    # 1) Wrap any lambda/capture callbacks in ea
    orig_ea = ea
    ea = wrap_fns(ea)

    # 2) For sort/2 with a lambda sorter, use the original (unwrapped) callback
    #    to avoid double-wrapping — wrap_sort does its own destructuring.
    ea =
      case {f, orig_ea} do
        {:sort, [s]} -> if function?(s), do: [wrap_sort(s, mfunc)], else: ea
        _ -> ea
      end

    case f do
      g when g in [:all?, :any?, :each, :map, :flat_map, :frequencies_by, :find_value] ->
        on_first(ea, fn w -> {:ok, mk.(g, [w])} end)

      g when g in [:reduce, :reduce_while] ->
        case ea do
          [acc, cb] -> if function?(cb), do: {:ok, mk.(g, [acc, cb])}, else: :no
          _ -> :no
        end

      :count ->
        case ea do
          [] -> {:ok, mk.(:count, [])}
          [cb | _] -> if function?(cb), do: {:ok, mk.(:count, [cb])}, else: :no
        end

      :max ->
        on_empty(ea, fn -> {:ok, pe_el(pm, mk.(:max_by, [ex(mfunc)]), ei(mfunc))} end)

      :min ->
        on_empty(ea, fn -> {:ok, pe_el(pm, mk.(:min_by, [ex(mfunc)]), ei(mfunc))} end)

      g when g in [:max_by, :min_by] ->
        on_first(ea, fn w -> {:ok, pe_el(pm, mk.(g, [w]), ei(mfunc))} end)

      :sum ->
        on_empty(ea, fn -> {:ok, mk.(:reduce, [0, rc(mfunc, :+)])} end)

      :product ->
        on_empty(ea, fn -> {:ok, mk.(:reduce, [1, rc(mfunc, :*)])} end)

      :at ->
        case ea do
          [idx] -> {:ok, nc(sn(:at, [ma, idx]), mfunc, nil)}
          [idx, default] -> {:ok, nc(sn(:at, [ma, idx]), mfunc, default)}
          _ -> :no
        end

      :find ->
        case ea do
          [cb] ->
            if function?(cb), do: {:ok, nc(sn(:find, [ma, cb]), mfunc, nil)}, else: :no

          [default, cb] ->
            if function?(cb), do: {:ok, nc(sn(:find, [ma, cb]), mfunc, default)}, else: :no

          _ ->
            :no
        end

      :random ->
        on_empty(ea, fn -> {:ok, pe_el(pm, mk.(:random, []), ei(mfunc))} end)

      :join ->
        case ea do
          [] -> {:ok, sn(:map_join, [ma, "", ex(mfunc)])}
          [sep] -> {:ok, sn(:map_join, [ma, sep, ex(mfunc)])}
          _ -> :no
        end

      :empty? ->
        {:ok, mk.(:empty?, ea)}

      g when g in [:filter, :reject] ->
        on_first(ea, fn w -> {:ok, mk2.(mk.(g, [w]), :map, [ex(mfunc)])} end)

      :sort ->
        case ea do
          [] ->
            {:ok, mk2.(mk.(:sort_by, [ex(mfunc)]), :map, [ex(mfunc)])}

          [s] ->
            cond do
              is_atom(s) ->
                {:ok, mk2.(mk.(:sort_by, [ex(mfunc), s]), :map, [ex(mfunc)])}

              function?(s) ->
                {:ok, mk2.(mk.(:sort, [s]), :map, [ex(mfunc)])}

              true ->
                :no
            end

          _ ->
            :no
        end

      :sort_by ->
        on_first(ea, fn w ->
          opts = tl(ea)
          {:ok, mk2.(mk.(:sort_by, [w | opts]), :map, [ex(mfunc)])}
        end)

      g when g in [:uniq, :dedup] ->
        on_empty(ea, fn ->
          by = if g == :uniq, do: :uniq_by, else: :dedup_by
          {:ok, mk2.(mk.(by, [ex(mfunc)]), :map, [ex(mfunc)])}
        end)

      g when g in [:uniq_by, :dedup_by] ->
        on_first(ea, fn w -> {:ok, mk2.(mk.(g, [w]), :map, [ex(mfunc)])} end)

      g when g in [:take_while, :drop_while] ->
        on_first(ea, fn w -> {:ok, mk2.(mk.(g, [w]), :map, [ex(mfunc)])} end)

      g when g in [:take, :drop, :reverse, :sample, :shuffle, :slice, :take_every, :drop_every] ->
        {:ok, mk2.(mk.(g, ea), :map, [ex(mfunc)])}

      :frequencies ->
        on_empty(ea, fn -> {:ok, mk.(:frequencies_by, [ex(mfunc)])} end)

      :group_by ->
        case ea do
          [kc, vc] ->
            if function?(kc) and function?(vc), do: {:ok, mk.(:group_by, [kc, vc])}, else: :no

          _ ->
            :no
        end

      _ ->
        :no
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # callback wrapping
  # ═══════════════════════════════════════════════════════════════════

  # Walk a list of args and wrap any lambdas or captures
  defp wrap_fns(args) do
    Enum.map(args, fn
      {:fn, _, _} = cb ->
        wrap_cb(cb)

      {:&, _, [{:/, _, [_, 1]}]} = cb ->
        wrap_cb(cb)

      {:&, _, [_]} = cb ->
        # Complex capture like &(length(&1) > 1) — convert to fn first
        case capture_to_fn(cb) do
          {:fn, _, _} = converted -> wrap_cb(converted)
          _ -> cb
        end

      other ->
        other
    end)
  end

  # fn patterns... -> body → fn {_k, patterns...} -> body
  defp wrap_cb({:fn, fm, clauses}) do
    new =
      Enum.map(clauses, fn {:->, am, [head, body]} ->
        {:->, am, [destructure_head(head), body]}
      end)

    {:fn, fm, new}
  end

  # &Mod.func/1 → fn {_k, x} -> Mod.func(x) end
  defp wrap_cb({:&, cm, [{:/, _, [ref, 1]}]}) do
    var = {:x, [], nil}
    {:fn, cm, [{:->, [], [[df(var)], rebuild_call(ref, var)]}]}
  end

  # &(expr using &1) → fn x -> expr end
  # Converts a complex capture into a fn so wrap_cb can destructure it.
  # Returns the original capture unchanged if it uses &2+ (multi-arity).
  defp capture_to_fn({:&, cm, [body]}) do
    if uses_higher_capture?(body) do
      {:&, cm, [body]}
    else
      var = {:x, [], nil}

      new_body =
        Macro.prewalk(body, fn
          {:&, _, [1]} -> var
          node -> node
        end)

      {:fn, cm, [{:->, [], [[var], new_body]}]}
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

  # fn(a, b) -> body → fn({_, a}, {_, b}) -> body  (for sort/2 comparators)
  defp wrap_sort({:fn, fm, clauses}, mf) do
    new =
      Enum.map(clauses, fn {:->, am, [head, body]} ->
        {:->, am, [sorter_head(head, mf), body]}
      end)

    {:fn, fm, new}
  end

  defp destructure_head([{:when, wm, [pattern, guard]} | rest]) do
    [{:when, wm, [df(pattern), guard]} | rest]
  end

  defp destructure_head([first | rest]) do
    [df(first) | rest]
  end

  defp destructure_head([]), do: []

  defp sorter_head([{:when, wm, [p1, guard]}, p2 | rest], _mf) do
    [{:when, wm, [df(p1), guard]}, df(p2) | rest]
  end

  defp sorter_head([p1, p2 | rest], _mf) do
    [df(p1), df(p2) | rest]
  end

  defp sorter_head(other, _mf), do: other

  defp df(pattern), do: {{:_k, [], nil}, pattern}

  defp rebuild_call({name, _meta, ctx}, arg) when is_atom(ctx) do
    {name, [], [arg]}
  end

  defp rebuild_call({{:., _, [{:__aliases__, _, mod}, func]}, _, []}, arg) do
    {{:., [], [{:__aliases__, [], mod}, func]}, [], [arg]}
  end

  # ═══════════════════════════════════════════════════════════════════
  # dispatch helpers
  # ═══════════════════════════════════════════════════════════════════

  defp on_first([cb | _], fun), do: fun.(cb)
  defp on_first(_, _), do: :no

  defp on_empty([], fun), do: fun.()
  defp on_empty(_, _), do: :no

  defp pick({:ok, node}, _fb), do: node
  defp pick(:no, fb), do: fb

  # Runtime check: is this node a fn or &func/1?
  defp function?({:fn, _, _}), do: true
  defp function?({:&, _, [{:/, _, [_, 1]}]}), do: true
  defp function?(_), do: false

  # ═══════════════════════════════════════════════════════════════════
  # AST builders
  # ═══════════════════════════════════════════════════════════════════

  # Enum.f(args) with explicit metadata
  defp en(d, a, c, f, x), do: {{:., d, [{:__aliases__, a, [:Enum]}, f]}, c, x}

  # Enum.f(args) with empty metadata
  defp sn(f, x), do: {{:., [], [{:__aliases__, [], [:Enum]}, f]}, [], x}

  # left |> Enum.f(args)
  defp pe(pm, l, f, x), do: {:|>, pm, [l, sn(f, x)]}

  defp el(t, i), do: {:elem, [], [t, i]}

  defp pe_el(pm, mid, i), do: {:|>, pm, [mid, {:elem, [], [i]}]}

  defp ei(:values), do: 1
  defp ei(:keys), do: 0

  defp ex(:values), do: {:fn, [], [{:->, [], [[{{:_, [], nil}, {:v, [], nil}}], {:v, [], nil}]}]}
  defp ex(:keys), do: {:fn, [], [{:->, [], [[{{:k, [], nil}, {:_, [], nil}}], {:k, [], nil}]}]}

  defp ev(:values), do: {{:_k, [], nil}, {:v, [], nil}}
  defp ev(:keys), do: {{:k, [], nil}, {:_v, [], nil}}

  defp vv(:values), do: {:v, [], nil}
  defp vv(:keys), do: {:k, [], nil}

  defp rc(mf, op) do
    acc = {:acc, [], nil}
    {:fn, [], [{:->, [], [[ev(mf), acc], {op, [], [acc, vv(mf)]}]}]}
  end

  defp nc(inner, mf, default) do
    {:case, [], [inner, [do: [{:->, [], [[nil], default]}, {:->, [], [[ev(mf)], vv(mf)]}]]]}
  end

  # ═══════════════════════════════════════════════════════════════════
  # issue + fixable?
  # ═══════════════════════════════════════════════════════════════════

  defp issue(mf, ef, meta) do
    %Issue{
      rule: :no_map_keys_or_values_for_iteration,
      message:
        "`Map.#{mf}/1` creates an intermediate list before passing to `Enum.#{ef}`. " <>
          "Iterate the map directly — `Enum` functions accept maps and yield `{key, value}` pairs.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp fixable?(f, r) do
    f in @fixable_funcs and not (f == :group_by and length(r) < 2)
  end
end
