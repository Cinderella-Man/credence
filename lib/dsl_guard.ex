defmodule Credence.DslGuard do
  @moduledoc """
  Keeps Pattern rules out of macro blocks that **reinterpret** plain Elixir AST.

  ## The problem this solves

  Credence rules read raw Elixir AST and assume plain-Elixir semantics. Some
  macros re-read that same AST with *different* meaning, so a rewrite that is
  valid in plain Elixir becomes wrong — and still compiles, so it fails only at
  runtime. The reported case (Ash):

      # plain Elixir: !x ≡ not x. Inside Ash.Expr.expr/1 they are NOT the same.
      expr(if cond do false else x end)        # not-negation, translates to SQL
      expr(if !cond do x else false end)        # %Ash.Query.Call{name: :!} — no SQL translation

  The same hazard exists for `Ecto.Query` macros (`!`/`&&`/`||` are compile
  errors; `x == nil` is a compile error; `is_nil` is required), `Nx.Defn`
  (`==`/`and`/`if` are element-wise tensor ops), and any other AST-reinterpreting
  DSL. See the divergence catalogue in the issue tracker.

  This module finds the **source ranges** of those blocks. Both Pattern gates
  derive from them — and from the same patches — so they cannot disagree:

    * `Credence.RuleHelpers.apply_rule_fix/3` drops any *single* patch whose range
      intersects an `unsafe_in_dsl/0` block (a fix on plain code elsewhere in the
      file still lands), and
    * `Credence.Pattern.analyze/2` suppresses a finding exactly when its line
      falls inside one of those *dropped* patch ranges
      (`RuleHelpers.dsl_dropped_ranges/3`). A finding is therefore reported iff its
      fix is applied — the two gates share one computation, not two views of it.

  ## Detection is mostly by SHAPE, not by import

  A parse-only tool cannot expand macros, so it cannot know that
  `use MyAppWeb, :live_view` brings `import Ecto.Query` into scope, nor that
  `use MyApp.Resource` re-exports `use Ash.Resource`. Keying on a literal
  top-level `import`/`use` therefore fails for the dominant real-world setups.
  Wherever a distinctive **call shape** exists we match that instead, since it
  survives wrappers, scoped imports and aliases:

    * `expr(...)`, `defn`/`defnp ...` — distinctive names, always treated as DSL.
    * `from(x in Y, ...)` — first argument is an `x in Source` expression (this
      also covers the keyword query syntax `from(p in P, where: ..., select: ...)`,
      since the whole `from` block range encloses the keywords).
    * Ecto pipe macros (`where`, `select`, `dynamic`, `join`, ...) — only when a
      **binding list** argument is present (`where([p], p.x == ^v)`). The binding
      list is Ecto's signature and is virtually unseen in plain code, so a plain
      `select(opts)` / `def dynamic(d)` is never mistaken for a query.
    * Qualified/aliased calls (`Ecto.Query.from`, `alias Ash.Expr; Expr.expr`) —
      resolved through the file's `alias` table.

  The one place shape is insufficient is Ash's `filter`/`calculate`/`aggregate`,
  which reinterpret their argument but are spelled like ordinary functions and
  carry no binding-list-style signature. A bare call to one of these is treated as
  `:ash_expr` **only** in a file that directly `import`s/`use`s an `Ash.*` module —
  a same-file signal strong enough to distinguish the Ash macro from a plain
  `filter/2` helper. This is the sole import-dependent path, so it does not cover
  a wrapper that hides the Ash `use` (`config :credence, dsl_macros:` handles
  those); the qualified `Ash.Query.filter` form is always covered above.

  ### Posture: conservative

  When in doubt we treat code as DSL. Over-detection only costs a *missed* fix
  (we skip a safe rewrite); under-detection would ship a *wrong* one. The known
  cost on the 500-package corpus is a handful of plain-Elixir antipatterns that
  merely share a line with a DSL call going unfixed.

  ### Limits (best-effort, not a guarantee)

  The macro set is a denylist. An AST-reinterpreting DSL that is neither built in
  nor configured is **not** protected. Extend coverage with:

      config :credence, dsl_macros: [:my_query_macro, ...]

  Names added there are matched as "always DSL" (like `expr`).
  """

  @typedoc "A Sourceror source range: `%{start: [line:, column:], end: [line:, column:]}`."
  @type range :: %{start: keyword(), end: keyword()}

  @typedoc "A DSL family — which library reinterprets the block."
  @type family :: :ash_expr | :ecto_query | :nx_defn

  @typedoc "A detected block: its family, source range, and AST node."
  @type block :: %{family: family(), range: range(), node: Macro.t()}

  @families [:ash_expr, :ecto_query, :nx_defn]

  @doc "The DSL families the guard knows about, in declaration order."
  @spec families() :: [family()]
  def families, do: @families

  # Distinctive macro names: low collision risk, high reinterpretation risk.
  # Matched regardless of imports/aliases (a plain function literally named
  # `expr` is rare, and treating one as DSL only forgoes a fix there).
  @always_names ~w(expr)a

  # Ash macros that reinterpret their expression argument but share their names
  # with ordinary functions (`filter`, `calculate`, `aggregate`), so — unlike
  # `expr` — a bare call cannot be treated as DSL by name alone (it would
  # over-suppress every plain `filter/2` helper). These are matched as `:ash_expr`
  # ONLY in a file that directly `import`s / `use`s an `Ash.*` module, which is a
  # strong same-file signal that a bare `filter(...)` is the Ash macro. This does
  # NOT cover the `use MyAppWeb, :resource` wrapper case (the import is hidden) —
  # for those, name the macro via `config :credence, dsl_macros: [:filter]`. The
  # qualified forms (`Ash.Query.filter`) are always covered via `qualified_family/2`.
  @ash_signal_names ~w(filter calculate aggregate)a

  # Numerical-definition forms (Nx). The whole body is reinterpreted, so the
  # def-form node range (which spans the body) is the block.
  @defn_names ~w(defn defnp)a

  # Ecto query pipe macros — ordinary English words, so matched ONLY when the
  # call carries a binding-list argument (`[p]`). Keyword `from(... where: ...)`
  # is covered separately by the enclosing `from` range.
  @ecto_pipe_names ~w(where or_where select select_merge having or_having
                      group_by order_by distinct join on dynamic windows
                      with_cte subquery)a

  # Forms whose first argument is a function head we must NOT treat as a call.
  @def_forms ~w(def defp defmacro defmacrop defguard defguardp)a

  @doc """
  Returns every reinterpreting-DSL block in `ast`, each tagged with its family.

  This is the single predicate behind both the analyze-side and fix-side gates,
  so the two can never disagree about what counts as DSL.
  """
  @spec block_ranges(Macro.t(), keyword()) :: [block()]
  def block_ranges(ast, opts \\ []) do
    ctx = %{
      ash: MapSet.new(@always_names ++ ash_signal_names(ast)),
      custom: MapSet.new(configured_names(opts)),
      heads: head_ids(ast),
      aliases: alias_map(ast)
    }

    {_ast, blocks} =
      Macro.prewalk(ast, [], fn node, acc -> {node, collect(node, acc, ctx)} end)

    Enum.reverse(blocks)
  end

  @doc """
  True when `line` falls within a block of one of `families` (used by the analyze
  gate with the firing rule's `unsafe_in_dsl/0`). `:all` matches every family;
  with the 2-arity form, any family.
  """
  @spec inside_block?(integer() | nil, [block()]) :: boolean()
  def inside_block?(line, blocks), do: inside_block?(line, blocks, :all)

  @spec inside_block?(integer() | nil, [block()], [family()] | :all) :: boolean()
  def inside_block?(nil, _blocks, _families), do: false

  def inside_block?(line, blocks, families) when is_integer(line) do
    blocks
    |> for_families(families)
    |> Enum.any?(fn %{start: [line: s, column: _], end: [line: e, column: _]} ->
      line >= s and line <= e
    end)
  end

  @doc """
  True when `line` falls inside any of `ranges` (plain Sourceror ranges). Used by
  the analyze-side gate against the *dropped* patch ranges from
  `Credence.RuleHelpers.dsl_dropped_ranges/3`, so finding-suppression tracks the
  fix-side patch drops exactly.
  """
  @spec line_in_ranges?(integer() | nil, [range()]) :: boolean()
  def line_in_ranges?(nil, _ranges), do: false

  def line_in_ranges?(line, ranges) when is_integer(line) do
    Enum.any?(ranges, fn %{start: [line: s, column: _], end: [line: e, column: _]} ->
      line >= s and line <= e
    end)
  end

  @doc """
  True when `patch` must be dropped because it touches a reinterpreting block of
  one of `families` (used by the fix gate with the firing rule's `unsafe_in_dsl/0`).

  `patch` may be a full patch (`%{range:, change:}`) or a bare range. A block is a
  hazard for the patch unless the patch *encloses* the whole block AND leaves that
  block **byte-for-byte unchanged** — i.e. the patch only re-renders an outer node
  and moves the block verbatim, with the actual rewrite landing on plain code
  outside it (the `relating_to_actor` shape: an `if` whose branch merely contains
  an `expr`). Every other overlap is a hazard: a patch *inside* a block (the
  reported `!`/`not` flip), a patch that reshapes the block, or a partial overlap.
  With only a range (no `change` to inspect) any intersection is a hazard, so this
  degrades to the original intersection test.
  """
  @spec patch_blocked?(range() | map(), [block()]) :: boolean()
  def patch_blocked?(patch, blocks), do: patch_blocked?(patch, blocks, :all)

  @spec patch_blocked?(range() | map(), [block()], [family()] | :all) :: boolean()
  def patch_blocked?(patch, blocks, families) do
    case patch_parts(patch) do
      {nil, _change} ->
        false

      {p_range, change} ->
        p_start = pos(p_range.start)
        p_end = pos(p_range.end)

        intersecting =
          blocks
          |> filter_family(families)
          |> Enum.filter(fn %{range: r} -> le(p_start, pos(r.end)) and le(pos(r.start), p_end) end)

        cond do
          intersecting == [] -> false
          # A block the patch does not fully enclose is an unconditional hazard:
          # the fix reaches inside it (the reported `!`/`not` flip) or straddles it.
          Enum.any?(intersecting, fn %{range: r} -> not encloses?(p_range, r) end) -> true
          # Every intersecting block is enclosed: safe only if the fix carried them
          # ALL through verbatim (the actual rewrite landed on plain code outside).
          true -> not all_preserved?(intersecting, change)
        end
    end
  end

  # A `%{range:, change:}` patch, a `%{range:}` patch, or a bare range map.
  defp patch_parts(%{range: %{start: _, end: _} = r, change: c}), do: {r, c}
  defp patch_parts(%{range: %{start: _, end: _} = r}), do: {r, nil}
  defp patch_parts(%{start: _, end: _} = r), do: {r, nil}
  defp patch_parts(_), do: {nil, nil}

  defp encloses?(outer, inner) do
    le(pos(outer.start), pos(inner.start)) and le(pos(inner.end), pos(outer.end))
  end

  # True when EVERY enclosed block survives verbatim in the patch's replacement.
  # Counts occurrences per distinct (metadata-stripped) block shape and requires
  # the replacement to contain at least as many of each — so two identical blocks
  # where the fix reshapes one (and the other aliases it) is still caught, not
  # masked by the surviving twin. A `change` that does not parse fails closed.
  defp all_preserved?(enclosed, change) when is_binary(change) do
    case Sourceror.parse_string(change) do
      {:ok, ast} ->
        required = enclosed |> Enum.map(&strip_meta(&1.node)) |> Enum.frequencies()
        Enum.all?(required, fn {shape, need} -> count_subtrees(ast, shape) >= need end)

      _ ->
        false
    end
  end

  defp all_preserved?(_enclosed, _change), do: false

  defp count_subtrees(ast, shape) do
    {_ast, n} =
      Macro.prewalk(ast, 0, fn node, acc ->
        {node, acc + if(strip_meta(node) == shape, do: 1, else: 0)}
      end)

    n
  end

  defp strip_meta(node) do
    Macro.prewalk(node, fn
      {form, meta, args} when is_list(meta) -> {form, [], args}
      other -> other
    end)
  end

  # Keep only the blocks whose family the caller cares about. A `:custom` block (a
  # user-configured macro) is included for any rule that declares *some* DSL
  # sensitivity, since we cannot know which built-in family an unknown DSL behaves
  # like.
  defp filter_family(blocks, :all), do: blocks

  defp filter_family(blocks, families) when is_list(families) do
    sensitive? = families != []
    for %{family: f} = block <- blocks, f in families or (f == :custom and sensitive?), do: block
  end

  defp for_families(blocks, families), do: blocks |> filter_family(families) |> Enum.map(& &1.range)

  # --- detection -------------------------------------------------------------

  defp collect({name, _meta, args} = node, acc, ctx)
       when is_atom(name) and is_list(args) and args != [] do
    cond do
      MapSet.member?(ctx.heads, call_id(node)) -> acc
      MapSet.member?(ctx.ash, name) -> add_block(node, :ash_expr, acc)
      MapSet.member?(ctx.custom, name) -> add_block(node, :custom, acc)
      name in @defn_names -> add_block(node, :nx_defn, acc)
      name == :from and from_query?(args) -> add_block(node, :ecto_query, acc)
      name in @ecto_pipe_names and ecto_pipe_query?(args) -> add_block(node, :ecto_query, acc)
      true -> acc
    end
  end

  # Qualified call: Ecto.Query.from(...), or alias Ash.Expr; Expr.expr(...).
  defp collect({{:., _, [{:__aliases__, _, prefix}, name]}, _meta, args} = node, acc, ctx)
       when is_list(args) and args != [] do
    full = Map.get(ctx.aliases, List.last(prefix), prefix)

    case qualified_family(full, name) do
      nil -> acc
      family -> add_block(node, family, acc)
    end
  end

  defp collect(_node, acc, _ctx), do: acc

  defp qualified_family([:Ecto, :Query], name) when name == :from or name in @ecto_pipe_names, do: :ecto_query
  defp qualified_family(mod, name) when mod in [[:Ash, :Expr], [:Ash, :Query]] and name in [:expr, :filter, :calculate, :aggregate], do: :ash_expr
  defp qualified_family([:Nx, :Defn], name) when name in @defn_names, do: :nx_defn
  defp qualified_family(_mod, _name), do: nil

  # `from(p in Post, ...)` — first arg is an `_ in _` (Sourceror may wrap it).
  defp from_query?([first | _]) do
    match?({:in, _, [_, _]}, first) or match?({:__block__, _, [{:in, _, [_, _]}]}, first)
  end

  defp from_query?(_), do: false

  # An Ecto pipe call is recognised by one of two signals:
  #
  #   * a **pin** (`^value`) anywhere in its arguments — `where(q, id: ^id)`,
  #     `where(q, [], ^dynamic)`, `order_by(q, ^order)`. A pin cannot appear in
  #     *compiling* plain code (it is a query/match construct), so it marks a query
  #     on its own, no binding argument needed. This covers the bindingless bare
  #     forms (Ecto reads a 2-arg `where(q, expr)` as an empty binding); or
  #   * a **binding marker** — a binding list (`[p]` / `[p, q]`) or an explicit
  #     empty binding (`[]`) — whose variable is actually **used as a query binding**:
  #     referenced somewhere else in the call (`p.field`, `struct(p, …)`,
  #     `count(p.id)`, a bare `p`), or an `in` expression is present.
  #
  # The binding list alone is not enough. Real libraries define their own
  # `select`/`group_by`/`join`: Explorer (DataFrames) has `select(df, [column])`
  # and `group_by(df, [group], opts)`; a string helper has `join(joiner, [a, b])`.
  # There the list variable is the *data*, never referenced as a binding, so the
  # call stays plain and its safe fix is not dropped (over-detection is NOT
  # compile-gate-backstopped — the code compiles, so the lost fix is permanent). A
  # genuine query DOES reference its binding (`select([p], p)`,
  # `where([g], within?(point, g))`) — that reference is the signal. `in` is
  # trusted only alongside a marker (`x in list` is ordinary code). Detection stays
  # shape-based, so it survives `use MyAppWeb` wrappers that hide `import Ecto.Query`.
  defp ecto_pipe_query?(args) do
    has_pin?(args) or (has_binding_marker?(args) and uses_binding?(args, binding_vars(args)))
  end

  # A pin (`^value`) anywhere in the arguments — a standalone query signal.
  defp has_pin?(args) do
    Enum.any?(args, fn arg ->
      {_ast, hit?} =
        Macro.prewalk(arg, false, fn
          {:^, _, [_]} = n, _acc -> {n, true}
          n, acc -> {n, acc}
        end)

      hit?
    end)
  end

  defp has_binding_marker?(args), do: Enum.any?(args, &(binding_list?(&1) or empty_binding?(&1)))

  # A binding list is `[p]` / `[p, q]` / `[_]` — a list whose elements are all
  # bare variables or `_`. Sourceror wraps list literals in a `:__block__`.
  defp binding_list?({:__block__, _, [list]}), do: binding_list?(list)
  defp binding_list?(list) when is_list(list) and list != [], do: Enum.all?(list, &var_or_underscore?/1)
  defp binding_list?(_), do: false

  # An explicit empty binding — `where(query, [], ^cond)` — a valid Ecto form that
  # `binding_list?/1` deliberately excludes (a bare `[]` value is too common to
  # treat as a binding on its own; it is admitted only with a query-shaped sibling).
  defp empty_binding?({:__block__, _, [[]]}), do: true
  defp empty_binding?([]), do: true
  defp empty_binding?(_), do: false

  defp var_or_underscore?({name, _meta, ctx}) when is_atom(name) and (is_atom(ctx) or is_nil(ctx)), do: true
  defp var_or_underscore?(_), do: false

  # The variable names introduced by every binding-list argument (ignoring `_`,
  # which is never referenced back).
  defp binding_vars(args) do
    for arg <- args,
        list = unwrap_list(arg),
        is_list(list),
        {name, _meta, ctx} <- list,
        is_atom(name) and name != :_ and (is_atom(ctx) or is_nil(ctx)),
        into: MapSet.new(),
        do: name
  end

  defp unwrap_list({:__block__, _, [list]}), do: list
  defp unwrap_list(list) when is_list(list), do: list
  defp unwrap_list(_), do: nil

  # True when a binding-marker call uses its binding the way a query does: a bound
  # variable is referenced in a NON-binding-list argument (`p.field`,
  # `struct(p, ...)`, a bare `p`), or an `in` expression is present
  # (`c in assoc(p, ...)`). A namesake call whose list variable is never referenced
  # elsewhere — Explorer's `select(df, [column])` — stays plain. (Pins are handled
  # separately by `has_pin?/1`, since they need no marker.)
  defp uses_binding?(args, vars) do
    others = Enum.reject(args, &binding_list?/1)

    (MapSet.size(vars) > 0 and Enum.any?(others, &references_var?(&1, vars))) or
      Enum.any?(args, &has_in?/1)
  end

  defp references_var?(arg, vars) do
    {_ast, hit?} =
      Macro.prewalk(arg, false, fn
        {v, _meta, ctx} = n, acc when is_atom(v) and (is_atom(ctx) or is_nil(ctx)) ->
          {n, acc or MapSet.member?(vars, v)}

        n, acc ->
          {n, acc}
      end)

    hit?
  end

  defp has_in?(arg) do
    {_ast, hit?} = Macro.prewalk(arg, false, fn {:in, _, [_, _]} = n, _ -> {n, true}; n, acc -> {n, acc} end)
    hit?
  end

  # The (name, arity) of every function head, so a call that is actually a head
  # (`def dynamic(descr)`) is excluded. Captured at the parent `def` so we have
  # the context a flat call-node walk lacks.
  defp head_ids(ast) do
    {_ast, ids} =
      Macro.prewalk(ast, MapSet.new(), fn
        {form, _, [{:when, _, [call | _]} | _]} = node, acc when form in @def_forms ->
          {node, MapSet.put(acc, call_id(call))}

        {form, _, [call | _]} = node, acc when form in @def_forms ->
          {node, MapSet.put(acc, call_id(call))}

        node, acc ->
          {node, acc}
      end)

    ids
  end

  defp call_id({name, _meta, args}) when is_list(args), do: {name, length(args)}
  defp call_id({name, _meta, _ctx}), do: {name, 0}
  defp call_id(other), do: other

  # `alias Ecto.Query` -> %{Query => [:Ecto, :Query]}; `alias Ecto.Query, as: Q`
  # -> %{Q => [:Ecto, :Query]}. Lets qualified-call detection see through aliases.
  defp alias_map(ast) do
    {_ast, map} =
      Macro.prewalk(ast, %{}, fn
        {:alias, _, [{:__aliases__, _, parts}]} = node, acc ->
          {node, Map.put(acc, List.last(parts), parts)}

        {:alias, _, [{:__aliases__, _, parts}, opts]} = node, acc when is_list(opts) ->
          {node, Map.put(acc, alias_as(opts) || List.last(parts), parts)}

        node, acc ->
          {node, acc}
      end)

    map
  end

  defp alias_as(opts) do
    Enum.find_value(opts, fn
      {{:__block__, _, [:as]}, {:__aliases__, _, [as]}} -> as
      {:as, {:__aliases__, _, [as]}} -> as
      _ -> nil
    end)
  end

  defp configured_names(opts) do
    (Application.get_env(:credence, :dsl_macros, []) ++ Keyword.get(opts, :dsl_macros, []))
    |> Enum.filter(&is_atom/1)
  end

  # Enable the ambiguous Ash macro names (`filter`/`calculate`/`aggregate`) only
  # when the file directly imports or uses an `Ash.*` module — a strong same-file
  # signal that a bare call to one of those names is the reinterpreting Ash macro
  # rather than a plain function. Best-effort: a `use MyAppWeb, :resource` wrapper
  # hides the import, so it is not covered here (use `config :credence, dsl_macros`).
  defp ash_signal_names(ast) do
    if ash_dsl_imported?(ast), do: @ash_signal_names, else: []
  end

  defp ash_dsl_imported?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {form, _, [{:__aliases__, _, [:Ash | _]} | _]} = node, _acc when form in [:import, :use] ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found?
  end

  # Fail safe: a detected DSL node whose range Sourceror cannot resolve still
  # gets a one-line range from its meta, so it is never silently left unguarded.
  defp add_block(node, family, acc) do
    case node_range(node) do
      nil -> acc
      range -> [%{family: family, range: range, node: node} | acc]
    end
  end

  defp node_range(node) do
    case Sourceror.get_range(node) do
      %{start: [line: _, column: _], end: [line: _, column: _]} = range -> range
      _ -> fallback_range(node)
    end
  end

  defp fallback_range({_callee, meta, _args}) when is_list(meta) do
    case Keyword.get(meta, :line) do
      line when is_integer(line) -> %{start: [line: line, column: 1], end: [line: line, column: 1]}
      _ -> nil
    end
  end

  defp fallback_range(_node), do: nil

  defp pos(position), do: {Keyword.fetch!(position, :line), Keyword.fetch!(position, :column)}

  defp le({l1, c1}, {l2, c2}), do: l1 < l2 or (l1 == l2 and c1 <= c2)
end
