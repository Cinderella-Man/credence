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

  ## Detection is by SHAPE, not by import

  A parse-only tool cannot expand macros, so it cannot know that
  `use MyAppWeb, :live_view` brings `import Ecto.Query` into scope, nor that
  `use MyApp.Resource` re-exports `use Ash.Resource`. Keying on a literal
  top-level `import`/`use` therefore fails for the dominant real-world setups.
  Instead we match the **call shape**, which survives wrappers, scoped imports
  and aliases:

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

  @typedoc "A detected block: its family and source range."
  @type block :: %{family: family(), range: range()}

  @families [:ash_expr, :ecto_query, :nx_defn]

  @doc "The DSL families the guard knows about, in declaration order."
  @spec families() :: [family()]
  def families, do: @families

  # Distinctive macro names: low collision risk, high reinterpretation risk.
  # Matched regardless of imports/aliases (a plain function literally named
  # `expr` is rare, and treating one as DSL only forgoes a fix there).
  @always_names ~w(expr)a

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
      ash: MapSet.new(@always_names),
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
  True when `patch_range` intersects a block of one of `families` (used by the fix
  gate with the firing rule's `unsafe_in_dsl/0`).

  Intersection (not mere containment) is what makes the gate catch both failure
  modes at once: a patch *inside* a block (the reported `!`/`not` flip) and a
  patch on an *enclosing* node that would re-render the block from AST.
  """
  @spec patch_blocked?(range() | map(), [block()]) :: boolean()
  def patch_blocked?(patch_range, blocks), do: patch_blocked?(patch_range, blocks, :all)

  @spec patch_blocked?(range() | map(), [block()], [family()] | :all) :: boolean()
  def patch_blocked?(%{start: ps, end: pe}, blocks, families) do
    p_start = pos(ps)
    p_end = pos(pe)

    blocks
    |> for_families(families)
    |> Enum.any?(fn %{start: bs, end: be} -> le(p_start, pos(be)) and le(pos(bs), p_end) end)
  end

  def patch_blocked?(_no_range, _blocks, _families), do: false

  # Keep only the blocks whose family the caller cares about, and project to the
  # bare range the position math works on. A `:custom` block (a user-configured
  # macro) is included for any rule that declares *some* DSL sensitivity, since we
  # cannot know which built-in family an unknown DSL behaves like.
  defp for_families(blocks, :all), do: Enum.map(blocks, & &1.range)

  defp for_families(blocks, families) when is_list(families) do
    sensitive? = families != []

    for %{family: f, range: range} <- blocks, f in families or (f == :custom and sensitive?),
        do: range
  end

  # --- detection -------------------------------------------------------------

  defp collect({name, _meta, args} = node, acc, ctx)
       when is_atom(name) and is_list(args) and args != [] do
    cond do
      MapSet.member?(ctx.heads, call_id(node)) -> acc
      MapSet.member?(ctx.ash, name) -> add_block(node, :ash_expr, acc)
      MapSet.member?(ctx.custom, name) -> add_block(node, :custom, acc)
      name in @defn_names -> add_block(node, :nx_defn, acc)
      name == :from and from_query?(args) -> add_block(node, :ecto_query, acc)
      name in @ecto_pipe_names and Enum.any?(args, &binding_list?/1) -> add_block(node, :ecto_query, acc)
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

  # A binding list is `[p]` / `[p, q]` / `[_]` — a list whose elements are all
  # bare variables or `_`. Sourceror wraps list literals in a `:__block__`.
  defp binding_list?({:__block__, _, [list]}), do: binding_list?(list)
  defp binding_list?(list) when is_list(list) and list != [], do: Enum.all?(list, &var_or_underscore?/1)
  defp binding_list?(_), do: false

  defp var_or_underscore?({name, _meta, ctx}) when is_atom(name) and (is_atom(ctx) or is_nil(ctx)), do: true
  defp var_or_underscore?(_), do: false

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

  # Fail safe: a detected DSL node whose range Sourceror cannot resolve still
  # gets a one-line range from its meta, so it is never silently left unguarded.
  defp add_block(node, family, acc) do
    case node_range(node) do
      nil -> acc
      range -> [%{family: family, range: range} | acc]
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
