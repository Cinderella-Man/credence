defmodule Credence.Pattern.PreferMapIntersectOverMapsetIntersection do
  @moduledoc """
  Detects MapSet-based intersection of map keys that can be replaced with
  `Map.intersect/3` (Elixir 1.14+).

  The verbose pipeline `Map.keys(a) |> MapSet.new() |> MapSet.intersection(MapSet.new(Map.keys(b))) |> MapSet.to_list()`
  followed by an `Enum.map` that fetches and merges values from both maps
  can be replaced with a single `Map.intersect/3` call.

  ## How narrow this is, measured

  docs/12 C12(c) called this rule over-fit in shape. It is: probed against eight
  spellings an author would plausibly write, it fires on **two**. What it
  requires, in full — a `common_keys` binding rather than an inlined pipeline,
  `Map.keys(x) |> MapSet.new()` piped in that exact direction, an explicit
  `MapSet.to_list()`, `Map.fetch!` rather than `Map.get`, and a trailing
  `Enum.sort()`.

  Three of those five are load-bearing for equivalence and must NOT be widened:

    * **the trailing `Enum.sort()`** — `Map.intersect/3` returns a map, so
      producing a sorted list is what makes the rewrite order-identical. Without
      it the original returns an unsorted list and the repair would silently
      reorder the result.
    * **`Map.fetch!`** — and the reason first written here was wrong, so it is worth
      stating what actually held. The claim was "`Map.get` returns `nil` … the two
      differ the moment the pipeline is edited". Within the shape as documented they
      cannot differ at all: the keys provably come from
      `Map.keys(f1) ∩ Map.keys(f2)`, so `Map.fetch!` never raises and `Map.get` never
      reaches its default. What made the distinction real was a **defect**, not the
      shape — nothing gated an intervening statement from rebinding `freq1`, and with
      one, `Map.fetch!` raised `KeyError` where `Map.get` would have returned `nil`
      and the repair diverged from both. That hole is now closed by
      `operands_untouched_between?/5`, which makes `Map.get` a genuinely free widen
      rather than a refused one. It is still not taken — the check test pins the
      boundary and the same fire-rate argument applies — but it is now on the
      incidental list below, not the load-bearing one.
    * **the `min`/`max` combiner** is already generalised — both fire, and the
      combiner is carried into the repair rather than assumed.

  Three are incidental and could be widened safely: an inlined pipeline with no
  `common_keys` binding, `MapSet.new(Map.keys(x))` written as a call rather than a pipe,
  and — since the rebinding gate landed — `Map.get` in place of `Map.fetch!`. That is the whole available gain, and it is not taken here.
  Widening a five-stage structural matcher is not a one-line change, and this
  project's standing rule is that a wider rule is often strictly worse than a
  narrow one — so the measurement is recorded, the boundary is pinned in
  `..._check_test.exs`, and the decision is left to whoever has a corpus fire-rate
  to weigh it against (C12(b), blocked on the harness's H10/H11).

  ## Bad

      common_keys =
        Map.keys(freq1)
        |> MapSet.new()
        |> MapSet.intersection(MapSet.new(Map.keys(freq2)))
        |> MapSet.to_list()

      common_keys
      |> Enum.map(fn element ->
        count1 = Map.fetch!(freq1, element)
        count2 = Map.fetch!(freq2, element)
        {element, min(count1, count2)}
      end)
      |> Enum.sort()

  ## Good

      freq1
      |> Map.intersect(freq2, fn _key, count1, count2 -> min(count1, count2) end)
      |> Enum.sort()

  ## Scope — what makes the rewrite safe

  The whole two-statement shape must be present (the rule flags and fixes the
  *same* node — never one without the other), and every gap that could change
  the answer is closed:

  - **The intersection assignment feeds exactly one `Enum.map |> Enum.sort`.**
    The assigned variable is used once; the fix deletes its binding, so a second
    use would strand it unbound.
  - **`freq1`/`freq2` are bare variables.** They are spliced verbatim into the
    `Map.intersect/3` call.
  - **The merge expression is a pure arithmetic combination of `count1`/`count2`
    and numeric literals** (`min`/`max`/`+`/`-`/`*`/`div`/`rem`/`abs`). This both
    rules out a merge that references the `element` key (which becomes `_key` and
    would be unbound) and guarantees the result is independent of evaluation
    order — `MapSet.to_list` and `Map.intersect` build maps with the *same* key
    set, so they enumerate it identically, and the final `Enum.sort/1` is a total
    order over the whole `{key, value}` tuple either way.

  ## Why the fix keeps `Enum.sort/1` rather than `Enum.sort_by(key)`

  It used to emit `Enum.sort_by(fn {key, _value} -> key end)` on the argument
  that "keys are unique, so sorting by key equals sorting by the whole tuple".
  That is false: map keys are unique under `===`, but `Enum.sort/1` orders by
  Erlang **term** order, under which `1` and `1.0` compare *equal*. Two entries
  whose keys are `==`-but-not-`===` therefore tie under `sort_by(key)` (stable —
  map order wins) while `Enum.sort/1` breaks the tie on the value. On
  `lst1 = [1, 1, 1, 1.0]`, `lst2 = [1, 1, 1, 1.0, 1.0]` the original returns
  `[{1.0, 1}, {1, 3}]` and the `sort_by` rewrite returned `[{1, 3}, {1.0, 1}]`.
  Emitting the original's own `Enum.sort/1` removes the divergence entirely.
  """

  use Credence.Pattern.Rule
  # Safe in all three families: requires a `Map.keys |> MapSet.new |>
  # MapSet.intersection |> MapSet.to_list` binding plus an `Enum.map(fn ... end)
  # |> Enum.sort` over it in the same block; `MapSet.*`/`Enum.*` are never DSL-
  # expression constructs, and the arithmetic merge expression
  # (`+`/`-`/`*`/`div`/`rem`) is carried verbatim into the new `Map.intersect/3`
  # lambda, no operator changed. The source scan flags this rule because the
  # construct appears in it, but the matcher cannot reach a DSL expression, so
  # the deliberate answer is the empty list rather than an allowlist entry — the
  # fixture-level oracle does not flag it at all.
  @impl true
  def unsafe_in_dsl, do: []
  alias Credence.Issue
  alias Credence.RuleHelpers

  # Pure arithmetic operators/locals allowed in the merge expression.
  @pure_binops [:+, :-, :*, :min, :max, :div, :rem]

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:__block__, _, exprs} = node, acc when is_list(exprs) ->
          case analyze_block(exprs) do
            {:ok, %{meta: meta}} -> {node, [build_issue(meta) | acc]}
            :error -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)

    RuleHelpers.patches_from_ast_transform(ast, source, fn input ->
      Macro.postwalk(input, fn
        {:__block__, meta, exprs} when is_list(exprs) ->
          case transform_block(exprs) do
            {:ok, new_exprs} -> {:__block__, meta, new_exprs}
            :error -> {:__block__, meta, exprs}
          end

        node ->
          node
      end)
    end)
  end

  # ── block analysis (shared by check and fix) ───────────────────────

  defp analyze_block(exprs) do
    with {:ok, assign_idx, var_name, freq1, freq2, meta} <- find_mapset_assignment(exprs),
         true <- bare_var?(freq1) and bare_var?(freq2),
         {:ok, map_idx, count1, count2, merge_expr} <-
           find_enum_map(exprs, assign_idx + 1, var_name, freq1, freq2),
         true <- operands_untouched_between?(exprs, assign_idx, map_idx, freq1, freq2),
         true <- pure_merge?(merge_expr, count1, count2),
         true <- var_used_once?(exprs, var_name) do
      {:ok,
       %{
         assign_idx: assign_idx,
         map_idx: map_idx,
         freq1: freq1,
         freq2: freq2,
         count1: count1,
         count2: count2,
         merge_expr: merge_expr,
         meta: meta
       }}
    else
      _ -> :error
    end
  end

  defp transform_block(exprs) do
    case analyze_block(exprs) do
      {:ok, info} ->
        replacement =
          build_map_intersect(info.freq1, info.freq2, {info.count1, info.count2, info.merge_expr})

        new_exprs =
          exprs
          |> Enum.with_index()
          |> Enum.flat_map(fn
            {_, idx} when idx == info.assign_idx -> []
            {_, idx} when idx == info.map_idx -> [replacement]
            {expr, _} -> [expr]
          end)

        {:ok, new_exprs}

      :error ->
        :error
    end
  end

  # ── detection helpers ──────────────────────────────────────────────

  # Find assignment: var_name = Map.keys(a) |> MapSet.new() |> ...
  defp find_mapset_assignment(exprs) do
    exprs
    |> Enum.with_index()
    |> Enum.find_value(:error, fn
      {{:=, meta, [{var_name, _, nil}, pipeline]}, idx} ->
        case extract_mapset_pipeline_vars(pipeline) do
          {:ok, freq1, freq2} -> {:ok, idx, var_name, freq1, freq2, meta}
          :error -> nil
        end

      _ ->
        nil
    end)
  end

  defp extract_mapset_pipeline_vars(node) do
    case node do
      {:|>, _,
       [
         {:|>, _,
          [
            {:|>, _,
             [
               {{:., _, [{:__aliases__, _, [:Map]}, :keys]}, _, [freq1]},
               {{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, _, []}
             ]},
            {{:., _, [{:__aliases__, _, [:MapSet]}, :intersection]}, _,
             [
               {{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, _,
                [
                  {{:., _, [{:__aliases__, _, [:Map]}, :keys]}, _, [freq2]}
                ]}
             ]}
          ]},
         {{:., _, [{:__aliases__, _, [:MapSet]}, :to_list]}, _, []}
       ]} ->
        {:ok, freq1, freq2}

      _ ->
        :error
    end
  end

  # Find Enum.map(var, fn ...) |> Enum.sort() using the assigned variable
  defp find_enum_map(exprs, start_idx, var_name, freq1_ast, freq2_ast) do
    freq1_name = elem(freq1_ast, 0)
    freq2_name = elem(freq2_ast, 0)

    exprs
    |> Enum.drop(start_idx)
    |> Enum.with_index(start_idx)
    |> Enum.find_value(:error, fn {expr, idx} ->
      case extract_enum_map_merge(expr, var_name, freq1_name, freq2_name) do
        {:ok, result} -> {:ok, idx, elem(result, 0), elem(result, 1), elem(result, 2)}
        :error -> nil
      end
    end)
  end

  defp extract_enum_map_merge(expr, var_name, freq1_name, freq2_name) do
    case expr do
      {:|>, _,
       [
         {:|>, _,
          [
            {^var_name, _, nil},
            {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [fn_expr]}
          ]},
         {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, []}
       ]} ->
        extract_merge_fn(fn_expr, freq1_name, freq2_name)

      _ ->
        :error
    end
  end

  defp extract_merge_fn(fn_expr, freq1_name, freq2_name) do
    case fn_expr do
      {:fn, _,
       [
         {:->, _,
          [
            [{elem_var, _, nil}],
            {:__block__, _, stmts}
          ]}
       ]} ->
        match_merge_stmts(stmts, elem_var, freq1_name, freq2_name)

      _ ->
        :error
    end
  end

  defp match_merge_stmts(stmts, elem_var, freq1_name, freq2_name) do
    case stmts do
      [
        {:=, _,
         [
           {count1, _, nil},
           {{:., _, [{:__aliases__, _, [:Map]}, :fetch!]}, _,
            [{^freq1_name, _, nil}, {^elem_var, _, nil}]}
         ]},
        {:=, _,
         [
           {count2, _, nil},
           {{:., _, [{:__aliases__, _, [:Map]}, :fetch!]}, _,
            [{^freq2_name, _, nil}, {^elem_var, _, nil}]}
         ]},
        {:__block__, _, [{{^elem_var, _, nil}, merge_expr}]}
      ]
      when count1 != count2 ->
        {:ok, {count1, count2, merge_expr}}

      _ ->
        :error
    end
  end

  # ── safety gates ───────────────────────────────────────────────────

  defp bare_var?({:__block__, _, [inner]}), do: bare_var?(inner)
  defp bare_var?({name, _, nil}) when is_atom(name), do: true
  defp bare_var?(_), do: false

  # The merge is a pure arithmetic combination of `count1`/`count2` and numeric
  # literals only. This excludes side effects (so the differing key-enumeration
  # order of MapSet vs Map.intersect is unobservable) and any reference to the
  # `element` key (which the rewrite drops to `_key`).
  defp pure_merge?({:__block__, _, [inner]}, c1, c2), do: pure_merge?(inner, c1, c2)
  defp pure_merge?({name, _, nil}, c1, c2) when name == c1 or name == c2, do: true
  defp pure_merge?(n, _c1, _c2) when is_integer(n) or is_float(n), do: true

  defp pure_merge?({op, _, [a, b]}, c1, c2) when op in @pure_binops,
    do: pure_merge?(a, c1, c2) and pure_merge?(b, c1, c2)

  defp pure_merge?({:-, _, [a]}, c1, c2), do: pure_merge?(a, c1, c2)
  defp pure_merge?({:abs, _, [a]}, c1, c2), do: pure_merge?(a, c1, c2)
  defp pure_merge?(_, _c1, _c2), do: false

  # The assigned variable is bound once and used exactly once (in the
  # `Enum.map`) — total of two occurrences across the block. The fix deletes the
  # binding, so any further use would be left unbound.
  defp var_used_once?(exprs, var_name) do
    Enum.reduce(exprs, 0, fn expr, acc ->
      {_, count} =
        Macro.prewalk(expr, 0, fn
          {^var_name, _, nil} = node, c -> {node, c + 1}
          node, c -> {node, c}
        end)

      acc + count
    end) == 2
  end

  # ── build replacement AST ─────────────────────────────────────────

  # `_key` unless a captured count is already called that. `_key` is an ordinary variable
  # — the underscore only suppresses the unused warning — so nothing stops an author
  # writing `_key = Map.fetch!(freq1, element)`, and `match_merge_stmts/4` admits it
  # (its only name guard is `count1 != count2`). Emitting the literal atom then produced
  #
  #     fn _key, _key, count2 -> min(_key, count2) end
  #
  # which is a MATCH on one name, not two parameters: it compiles with warnings and
  # raises FunctionClauseError the moment `Map.intersect/3` calls it with a key that
  # differs from the value. Executed: the emitted form raised where the correct form
  # returned `[b: 2]`. Compiling means the accept/revert gate never saw it.
  defp key_param(count1, count2) do
    Stream.iterate(0, &(&1 + 1))
    |> Stream.map(fn
      0 -> :_key
      n -> :"_key#{n}"
    end)
    |> Enum.find(&(&1 not in [count1, count2]))
  end

  # The operands are matched by NAME only, and `find_enum_map/5` accepts the consumer at
  # any later index, so without this gate a statement in between may rebind `freq1` or
  # `freq2` — it is passed through verbatim while the emitted `Map.intersect/3` reads the
  # NEW value for both the key set and the values, where the original took the key set
  # from the OLD one. `var_used_once?/2` does not cover it: that guards the intersection
  # variable, never the operands.
  #
  # Executed, on `freq1 = Map.put(freq1, :x, 9)` between the two statements:
  #
  #     original  [b: 2]            repair  [b: 2, x: 7]     a key the original never had
  #     original  raises KeyError   repair  []               loud failure made silent
  #
  # (with `Map.delete(freq1, :b)` for the second row). Both compile, so the accept/revert
  # gate cannot see either — it reverts only on non-compiling output.
  #
  # Mentioning an operand is enough to decline, not just rebinding it. A read is in fact
  # harmless, but "does this statement mention the name" is checkable at a glance whereas
  # "does it rebind it" has to chase `=`, `for`/`with` generators, `case` results and
  # comprehension vars. Every fixture in all three test files has the two statements
  # adjacent, so the conservative form costs nothing measurable.
  # Adjacent statements have nothing in between, and the empty range would be descending
  # (`2..1`), which `Enum.slice/2` warns about rather than treating as empty.
  defp operands_untouched_between?(_exprs, assign_idx, map_idx, _freq1, _freq2)
       when map_idx <= assign_idx + 1,
       do: true

  defp operands_untouched_between?(exprs, assign_idx, map_idx, freq1, freq2) do
    names = [elem(freq1, 0), elem(freq2, 0)]

    exprs
    |> Enum.slice((assign_idx + 1)..(map_idx - 1)//1)
    |> Enum.all?(fn expr -> not mentions_any?(expr, names) end)
  end

  defp mentions_any?(node, names) do
    {_node, found} =
      Macro.prewalk(node, false, fn
        {name, _, context} = n, _found when is_atom(name) and is_atom(context) ->
          {n, name in names}

        n, found ->
          {n, found}
      end)

    found
  end

  defp build_map_intersect(freq1_ast, freq2_ast, {count1, count2, merge_expr}) do
    # fn _key, count1, count2 -> merge_expr end
    intersect_fn =
      {:fn, [],
       [
         {:->, [],
          [
            [{key_param(count1, count2), [], nil}, {count1, [], nil}, {count2, [], nil}],
            merge_expr
          ]}
       ]}

    # freq1 |> Map.intersect(freq2, intersect_fn) |> Enum.sort()
    #
    # `Enum.sort/1` — the ORIGINAL's own final step — not `Enum.sort_by(key)`:
    # `1` and `1.0` are distinct map keys that compare EQUAL in term order, so
    # sorting by key alone leaves them tied (and stably in map order) where the
    # original breaks the tie on the value. See the moduledoc.
    freq1_ast
    |> pipe({{:., [], [{:__aliases__, [], [:Map]}, :intersect]}, [], [freq2_ast, intersect_fn]})
    |> pipe({{:., [], [{:__aliases__, [], [:Enum]}, :sort]}, [], []})
  end

  defp pipe(left, right), do: {:|>, [], [left, right]}

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_map_intersect_over_mapset_intersection,
      message: "Use `Map.intersect/3` instead of MapSet intersection pipeline on map keys.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
