defmodule Credence.DslStaticScan do
  @moduledoc """
  Static (parse-only) scan that separates **DSL-classified** Pattern rules from
  **unclassified** ones, and says which of the unclassified ones look risky.

  ## Why a second scan exists

  `Credence.Pattern.DslSafetyClassificationTest` already asks the empirical
  question — it runs each rule's real fix over that rule's own `*_fix_test.exs`
  fixtures and diffs the reinterpreted-construct multiset. That oracle is exact
  for the inputs it sees and **blind to everything else**: a rule whose fixtures
  never happen to exhibit the reinterpreted construct produces an empty delta and
  passes silently (docs/12 C14).

  This module reads the rule's *source* instead of its fixtures. It never runs a
  fix, so it cannot say a rewrite is wrong; it says only whether the rule's fix
  code **builds or destructures** a construct the three known DSL families
  reinterpret, and whether the rule's matchers are anchored on shapes that cannot
  occur inside a DSL expression. The two scans are complementary: fixtures catch
  what the code does, source catches what the code could do on an input no fixture
  supplied.

  ## What it does NOT claim

  A static scan yields **possibly unsafe**, never *unsafe*. `:possibly_unsafe`
  means "this rule's fix builds or consumes a reinterpreted construct and nothing
  in its matchers rules out a DSL expression" — the correct response is a human
  reading the rule, not an automatic `unsafe_in_dsl/0` edit. Nothing here sets
  that callback.

  ## The construct universe is not re-derived here

  Two in-repo sources, composed:

    * **which constructs each family reinterprets** — `Credence.DslGuard`'s
      moduledoc: Ash.Expr rereads `!` (it is not `not`); Ecto.Query rejects
      `!`/`&&`/`||` and `x == nil` (and requires `is_nil`); Nx.Defn rereads
      `==`/`and`/`if` as element-wise tensor ops.
    * **the union oracle** — the `@ops`/`@ctrl` list already recorded in
      `test/dsl_safety_classification_test.exs`, described there as mirroring
      "the classification oracle the `unsafe_in_dsl` flags were derived from".

  Constructs in the union that `DslGuard`'s moduledoc does not attribute to a
  named family are reported as `:unattributed` rather than guessed at.

  ## Classification

  Each rule lands in exactly one bucket:

    * `:declared`        — the rule file contains an explicit `def unsafe_in_dsl`.
                           This is deliberately a **source** test, not
                           `rule.unsafe_in_dsl() != []`: at runtime a deliberate
                           `[]` and the inherited default `[]` are the same value,
                           which is exactly the invisibility docs/19 §2 row B
                           names. One shipped rule (`no_piped_regex_replace`)
                           declares `[]` on purpose, and only the source shows it.
    * `:verified_safe`   — carried on the hand-audited allowlist (passed in by the
                           caller; the live copy is `@verified_dsl_safe` in the
                           classification meta-test).
    * `:possibly_unsafe` — touches a reinterpreted construct, and at least one
                           matcher clause is not anchored on a shape that cannot
                           appear inside a DSL expression.
    * `:anchored`        — touches a reinterpreted construct, but **every** matcher
                           clause is anchored (a `def`/`defp` head, a module-level
                           form, or a call into a module no DSL expression grammar
                           can contain). This is the same argument the
                           `@verified_dsl_safe` entries make in prose.
    * `:no_construct`    — the fix code mentions no reinterpreted construct at all.

  ## Signals, in decreasing strength

    * `:build`     — the fix **constructs** a reinterpreted node: a quoted 3-tuple
                     literal such as `{:and, [], [a, b]}` in an expression
                     position, or a `quote do ... end` containing one.
    * `:build_str` — a string literal in fix code parses as Elixir and contains a
                     reinterpreted construct (rules that assemble replacement
                     source text rather than AST).
    * `:match`     — the fix **destructures** one: the same 3-tuple literal in a
                     pattern position, so the construct is in the fix's input and
                     may be removed or reshaped.
    * `:atom_ref`  — a bare construct atom used as a value (`when op in [:==, :!=]`,
                     `@ops ~w(+ - *)a`). Weakest: the direction is unknown.

  Pattern vs expression position is tracked structurally (`fn`/`case`/`receive`/
  `try` clause heads, `def`/`defp` heads, and the left of `=`/`<-` are patterns;
  everything else is an expression), so a rule that only *reads* `{:if, ...}` is
  never confused with one that *writes* it. A construct atom in **call-form
  position** — the rule's own `if`, `==`, `and`, `<>` — is deliberately not an
  occurrence: that is the rule's own Elixir, not code it emits.

  ## Scope: the fix, not the whole rule

  Only code reachable from `fix_patches/2` is scanned — transitively through local
  calls and through the module attributes that code references. A rule's `check/2`
  may mention any construct it likes; the gate is about what the rewrite does.
  ## What was deleted when the ledger emptied, and what was not

  docs/19 §3 says the sweep tooling goes once the C14 ledger is paid down. That
  happened on 2026-08-16, and the *paydown-ordering* machinery went with it:
  `shortlist/1` (rank the unclassified by signal strength), its `rank/1`, and the
  `pin/1` renderer — all three existed only to decide which of the 40 to read
  first, and there is no next one.

  `scan/2`, `tally/1` and `verified_dsl_safe_names/1` deliberately stay. They are
  not sweep tooling; they are what `dsl_static_scan_test.exs` runs on every suite
  pass to keep requirement 5 true for rules nobody has written yet. Deleting them
  would retire the gate along with the debt, and an empty ledger is the moment a
  ratchet is most worth keeping, not least.

  """

  @typedoc "One rule's static classification."
  @type entry :: %{
          name: String.t(),
          bucket: :declared | :verified_safe | :possibly_unsafe | :anchored | :no_construct,
          declared: :yes | :no,
          declared_value: String.t() | nil,
          constructs: [atom()],
          families: [atom()],
          signals: [atom()],
          builds: [atom()],
          matches: [atom()],
          anchored: boolean(),
          matcher_clauses: non_neg_integer(),
          unanchored_clauses: non_neg_integer(),
          evidence: [String.t()]
        }

  # --- the construct universe (composed, not re-derived) ---------------------

  # `test/dsl_safety_classification_test.exs` @ops ++ @ctrl.
  @ops ~w(! && || and or not == != === !== < > <= >= is_nil / div rem in + - * ** <> ++ --)a
  @ctrl ~w(if unless cond case with)a
  @constructs @ops ++ @ctrl

  # `Credence.DslGuard`'s moduledoc: the constructs it names, per family.
  # Anything else in @constructs is reported as `:unattributed`.
  @family_constructs %{
    ash_expr: ~w(! not)a,
    ecto_query: ~w(! && || == != is_nil)a,
    nx_defn: ~w(== and if)a
  }

  # --- anchors: shapes that cannot occur inside a DSL *expression* -----------

  # Definition forms and module-level constructs. A matcher keyed on one of these
  # is matching a definition, and a definition is never a DSL expression. (`receive`
  # / `try` / `spawn` are here for the same reason: no DSL expression grammar
  # admits them.)
  @def_anchors ~w(def defp defmacro defmacrop defguard defguardp defmodule defdelegate
                  defstruct defexception defimpl defprotocol @ use import require alias
                  receive try spawn spawn_link)a

  # Modules whose calls no DSL expression grammar can contain. This list is
  # deliberately SHORT and sourced from claims the repo has already audited, not
  # from a general sense of what "looks like plain Elixir":
  #
  #   * `Enum`/`Stream`/`List`/`MapSet` — the `@verified_dsl_safe` allowlist asserts
  #     this repeatedly ("`Enum.*` isn't valid in any DSL expression", "never data-
  #     layer expressions in Ash", "compile errors in Ecto/Nx").
  #   * process/IO/OTP modules — side-effecting calls, not translatable expressions
  #     in any of the three grammars.
  #
  # Notably ABSENT, on purpose:
  #   * `String` — `no_string_length_for_char_check` is declared `[:ash_expr]`
  #     precisely because Ash DOES build a translatable Call around
  #     `String.length(x) == 1`. A `String.*` matcher is not an anchor.
  #   * `Kernel` — `no_kernel_op_in_pipeline` is declared `:all`; `Kernel.+/2` and
  #     friends are exactly the reinterpreted operators.
  #   * `Map`/`Keyword`/`Tuple`/`Access` — unaudited; treated as reachable.
  @plain_only_modules ~w(Enum Stream List MapSet IO File Path Task Agent GenServer
                         Supervisor Process Registry Node System Application Logger)a

  @doc "The reinterpreted-construct universe this scan works over."
  @spec constructs() :: [atom()]
  def constructs, do: @constructs

  @doc """
  Scans every Pattern rule under `dir` and returns one `t:entry/0` per rule,
  sorted by name.

  `verified_safe` is the hand-audited allowlist (rule names as strings); pass the
  live `@verified_dsl_safe` keys so the two stay in step.
  """
  @spec scan(String.t(), [String.t()]) :: [entry()]
  def scan(dir \\ "lib/pattern", verified_safe \\ []) do
    verified = MapSet.new(verified_safe)

    dir
    |> Path.join("*.ex")
    |> Path.wildcard()
    |> Enum.reject(&(Path.basename(&1) == "rule.ex"))
    |> Enum.map(&scan_file(&1, verified))
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  The live `@verified_dsl_safe` keys, read out of the classification meta-test's
  **source**.

  Deliberately a source read rather than a duplicated list: the allowlist is a
  test module attribute, so it is not reachable at runtime from another module,
  and any copy of it here would be a second thing to keep in step. Reading the
  source means an entry added there is seen here on the next run — which is the
  point, since the two scans are supposed to answer the same question by
  different means.
  """
  @spec verified_dsl_safe_names(String.t()) :: [String.t()]
  def verified_dsl_safe_names(path \\ "test/dsl_safety_classification_test.exs") do
    path
    |> File.read!()
    |> Code.string_to_quoted!()
    |> Macro.prewalk([], fn
      {:@, _, [{:verified_dsl_safe, _, [{:%{}, _, pairs}]}]} = node, _acc ->
        {node, Enum.map(pairs, fn {key, _reason} -> key end)}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  @doc "Counts per bucket, for a one-line summary."
  @spec tally([entry()]) :: %{atom() => non_neg_integer()}
  def tally(entries), do: entries |> Enum.map(& &1.bucket) |> Enum.frequencies()

  # --- per-file ---------------------------------------------------------------

  defp scan_file(path, verified) do
    name = path |> Path.basename() |> String.replace_suffix(".ex", "")
    ast = path |> File.read!() |> Code.string_to_quoted!()

    defs = collect_defs(ast)
    attrs = collect_attrs(ast)
    {declared, declared_value} = declaration(ast)

    reachable = reachable_from(defs, attrs, {:fix_patches, 2})

    occurrences =
      reachable
      |> Enum.flat_map(fn {key, node, mode} -> walk(node, mode, key, []) end)
      |> Enum.uniq()

    {clause_owner, clauses} = entry_matcher(reachable)
    unanchored = Enum.reject(clauses, & &1.anchored)

    constructs = occurrences |> Enum.map(& &1.construct) |> Enum.uniq() |> Enum.sort()
    signals = occurrences |> Enum.map(& &1.kind) |> Enum.uniq() |> Enum.sort()

    anchored? = clauses != [] and unanchored == []

    bucket =
      cond do
        declared == :yes -> :declared
        MapSet.member?(verified, name) -> :verified_safe
        constructs == [] -> :no_construct
        anchored? -> :anchored
        true -> :possibly_unsafe
      end

    %{
      name: name,
      bucket: bucket,
      declared: declared,
      declared_value: declared_value,
      constructs: constructs,
      families: families_for(constructs),
      signals: signals,
      builds: kinds(occurrences, [:build, :build_str]),
      matches: kinds(occurrences, [:match]),
      anchored: anchored?,
      matcher_owner: clause_owner,
      heads: clauses,
      matcher_clauses: length(clauses),
      unanchored_clauses: length(unanchored),
      evidence: occurrences |> Enum.map(&evidence_line/1) |> Enum.uniq() |> Enum.sort()
    }
  end

  # Anchoring is decided by the **entry matcher** — the shallowest fix-reachable
  # function that destructures AST at all (`fix_patches/2` itself when the matcher
  # is inline; the helper it delegates to otherwise). That is the clause set which
  # decides whether the fix FIRES. Deeper helpers (`negate({:==, m, [a, b]})`)
  # only reshape a node the entry matcher already selected, so their unanchored
  # heads say nothing about reachability and would otherwise swamp the signal.
  defp entry_matcher(reachable) do
    scored =
      for {key, node, _mode} <- reachable,
          group = matcher_group(node, key),
          group != [],
          do: {key, node_kind(node), group}

    case scored do
      [] ->
        {nil, []}

      [{key, _kind, _} | _] ->
        heads = for {^key, :head, g} <- scored, c <- g, do: c

        # A function whose own clause heads destructure AST is the matcher; an
        # inner `fn`/`case` in the same function only reshapes what those heads
        # already selected, so it is not a second entry point.
        if heads != [] do
          {key, heads}
        else
          {key, scored |> Enum.find(&(elem(&1, 0) == key)) |> elem(2)}
        end
    end
  end

  defp node_kind({:__patterns__, _, _}), do: :head
  defp node_kind(_), do: :inner

  defp kinds(occurrences, wanted) do
    occurrences
    |> Enum.filter(&(&1.kind in wanted))
    |> Enum.map(& &1.construct)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp evidence_line(o) do
    where =
      case o.where do
        {:@, attr} -> "@#{attr}"
        {fun, arity} -> "#{fun}/#{arity}"
      end

    "#{o.kind} #{o.construct} @ #{where}:#{o.line}"
  end

  defp families_for(constructs) do
    named =
      for {family, cs} <- @family_constructs,
          Enum.any?(constructs, &(&1 in cs)),
          do: family

    unattributed? =
      Enum.any?(constructs, fn c ->
        not Enum.any?(@family_constructs, fn {_f, cs} -> c in cs end)
      end)

    Enum.sort(named ++ if(unattributed?, do: [:unattributed], else: []))
  end

  # --- declaration (source-level, deliberately) -------------------------------

  defp declaration(ast) do
    {_ast, found} =
      Macro.prewalk(ast, nil, fn
        {:def, _, [{:unsafe_in_dsl, _, args} | rest]} = node, _acc when args in [nil, []] ->
          {node, {:found, Macro.to_string(do_body(rest))}}

        node, acc ->
          {node, acc}
      end)

    case found do
      {:found, value} -> {:yes, value}
      nil -> {:no, nil}
    end
  end

  defp do_body([[{:do, body}]]), do: body
  defp do_body([body]), do: body
  defp do_body(other), do: other

  # --- definitions, attributes, reachability ----------------------------------

  defp collect_defs(ast) do
    {_ast, defs} =
      Macro.prewalk(ast, %{}, fn
        {form, _, [head | rest]} = node, acc when form in [:def, :defp] ->
          {node, Map.update(acc, def_key(head), [{head, rest}], &(&1 ++ [{head, rest}]))}

        node, acc ->
          {node, acc}
      end)

    defs
  end

  defp def_key({:when, _, [head | _]}), do: def_key(head)
  defp def_key({name, _, args}) when is_atom(name) and is_list(args), do: {name, length(args)}
  defp def_key({name, _, _}) when is_atom(name), do: {name, 0}
  defp def_key(_), do: {:__unknown__, 0}

  defp collect_attrs(ast) do
    {_ast, attrs} =
      Macro.prewalk(ast, %{}, fn
        {:@, _, [{name, _, [value]}]} = node, acc when is_atom(name) ->
          {node, Map.put_new(acc, name, value)}

        node, acc ->
          {node, acc}
      end)

    attrs
  end

  # Transitive closure from `entry` over local calls (matched by NAME, any arity —
  # a rule that delegates through a differently-arity'd helper still gets scanned)
  # and over the module attributes the reached code references. Each element is
  # `{where, node, mode}`: heads/guards enter in :pattern mode, bodies in :expr.
  defp reachable_from(defs, attrs, entry) do
    names = defs |> Map.keys() |> Enum.map(&elem(&1, 0)) |> MapSet.new()
    do_reach([entry], defs, attrs, names, MapSet.new(), [])
  end

  defp do_reach([], _defs, _attrs, _names, _seen, acc), do: acc

  defp do_reach([key | rest], defs, attrs, names, seen, acc) do
    if MapSet.member?(seen, key) do
      do_reach(rest, defs, attrs, names, seen, acc)
    else
      seen = MapSet.put(seen, key)
      clauses = Map.get(defs, key, [])

      nodes =
        Enum.flat_map(clauses, fn {head, body} ->
          [{key, head_patterns(head), :pattern}, {key, body, :expr}]
        end)

      called =
        clauses
        |> Enum.flat_map(fn {head, body} -> local_calls([head, body], names) end)
        |> Enum.flat_map(fn n ->
          for {m, a} = k <- Map.keys(defs), m == n, is_integer(a), do: k
        end)

      referenced =
        clauses
        |> Enum.flat_map(fn {head, body} -> attr_refs([head, body], attrs) end)
        |> Enum.map(fn a -> {{:@, a}, Map.fetch!(attrs, a), :expr} end)

      do_reach(rest ++ called, defs, attrs, names, seen, acc ++ nodes ++ referenced)
    end
  end

  # Head patterns, wrapped so `walk/4` and `matcher_clauses/2` see them as one
  # clause's pattern list. The `when` guard is folded in on purpose: a rule that
  # matches `{kind, meta, args} when kind in [:def, :defp]` carries its whole
  # anchor in the guard, and dropping the guard loses it.
  defp head_patterns({:when, _, [head | guard]}) do
    {:__patterns__, meta, args} = head_patterns(head)
    {:__patterns__, meta, args ++ guard}
  end

  defp head_patterns({name, meta, args}) when is_atom(name) and is_list(args),
    do: {:__patterns__, meta, args}

  defp head_patterns(_), do: {:__patterns__, [], []}

  defp local_calls(nodes, names) do
    nodes
    |> Enum.flat_map(fn node ->
      {_n, acc} =
        Macro.prewalk(node, [], fn
          {name, _, args} = n, acc when is_atom(name) and is_list(args) ->
            if MapSet.member?(names, name), do: {n, [name | acc]}, else: {n, acc}

          {name, _, ctx} = n, acc when is_atom(name) and is_atom(ctx) ->
            if MapSet.member?(names, name), do: {n, [name | acc]}, else: {n, acc}

          n, acc ->
            {n, acc}
        end)

      acc
    end)
    |> Enum.uniq()
  end

  defp attr_refs(nodes, attrs) do
    nodes
    |> Enum.flat_map(fn node ->
      {_n, acc} =
        Macro.prewalk(node, [], fn
          {:@, _, [{name, _, ctx}]} = n, acc when is_atom(name) and is_atom(ctx) ->
            if Map.has_key?(attrs, name), do: {n, [name | acc]}, else: {n, acc}

          n, acc ->
            {n, acc}
        end)

      acc
    end)
    |> Enum.uniq()
  end

  # --- the mode-aware walk -----------------------------------------------------

  # `mode` is :pattern inside a match position, :expr otherwise. An AST-node
  # literal seen in :pattern mode is a construct the fix CONSUMES; in :expr mode
  # it is one the fix PRODUCES.

  defp walk({:__patterns__, _, args}, _mode, where, acc) when is_list(args),
    do: Enum.reduce(args, acc, &walk(&1, :pattern, where, &2))

  # fn / case / receive / try clause heads are patterns; bodies are expressions.
  defp walk({:fn, _, clauses}, _mode, where, acc) when is_list(clauses),
    do: Enum.reduce(clauses, acc, &arrow(&1, :pattern, where, &2))

  defp walk({:case, _, [subject | blocks]}, mode, where, acc) do
    acc = walk(subject, mode, where, acc)
    walk_blocks(blocks, :pattern, where, acc)
  end

  defp walk({form, _, blocks}, _mode, where, acc)
       when form in [:receive, :try] and is_list(blocks),
       do: walk_blocks(blocks, :pattern, where, acc)

  # cond/with clause heads are expressions, not patterns.
  defp walk({:cond, _, blocks}, _mode, where, acc) when is_list(blocks),
    do: walk_blocks(blocks, :expr, where, acc)

  # `pattern = expr` / `pattern <- expr`.
  defp walk({op, _, [lhs, rhs]}, _mode, where, acc) when op in [:=, :<-] do
    acc = walk(lhs, :pattern, where, acc)
    walk(rhs, :expr, where, acc)
  end

  # A quoted 3-tuple AST literal: `{:and, [], [a, b]}` (build) or the same shape in
  # a pattern (match). The head atom is recorded here and NOT re-walked, so it does
  # not also register as a weak `:atom_ref`.
  # `&fun/arity` written as a quoted capture, in either shape a rule uses:
  # `{:&, meta, [spec]}` (three-element) or Sourceror's meta-elided `{:&, [spec]}`
  # pair. When `spec` is a `/` node that `/` is **capture arity, never division**,
  # and that holds whatever shape the arity takes — a bare `1`, a Sourceror
  # `{:__block__, _, [1]}` wrapper, or a pattern variable.
  #
  # `capture_arity?/1` below cannot see this, because it inspects the `/` node
  # alone and `{name, _, ctx}` is indistinguishable from a divisor once the
  # enclosing `&` is out of view; it recognises only a literal integer arity.
  # Matching `&fun/arity` with a variable arity is the ordinary way to write such
  # a matcher, and it was the largest single false-positive class in the first
  # scan — six rules whose only flagged construct was this `/`.
  defp walk({:{}, _meta, [:&, m, [spec]]}, mode, where, acc) do
    acc = walk(m, mode, where, acc)
    walk_capture_spec(spec, mode, where, acc)
  end

  defp walk({:&, [spec]}, mode, where, acc), do: walk_capture_spec(spec, mode, where, acc)

  defp walk({:{}, meta, [head, m, args]} = node, mode, where, acc) do
    acc = record_tuple(head, node, meta, mode, where, acc)
    acc = if is_atom(head), do: acc, else: walk(head, mode, where, acc)
    acc = walk(m, mode, where, acc)
    walk(args, mode, where, acc)
  end

  defp walk({:quote, meta, blocks}, _mode, where, acc) when is_list(blocks),
    do: quoted_constructs(blocks, meta, where, acc)

  # `~w(div rem)a` — a list of construct atoms written as a sigil.
  defp walk({:sigil_w, meta, [{:<<>>, _, parts}, _mods]}, _mode, where, acc) do
    line = Keyword.get(meta, :line, 0)

    parts
    |> Enum.filter(&is_binary/1)
    |> Enum.flat_map(&String.split(&1, ~r/\s+/, trim: true))
    |> Enum.filter(&(String.to_atom(&1) in @constructs))
    |> Enum.map(&occurrence(String.to_atom(&1), :atom_ref, where, line: line))
    |> Kernel.++(acc)
  end

  # A string literal, with or without interpolation.
  defp walk({:<<>>, meta, parts}, mode, where, acc) when is_list(parts) do
    acc = code_string(parts, Keyword.get(meta, :line, 0), mode, where, acc)

    parts
    |> Enum.reject(&is_binary/1)
    |> Enum.reduce(acc, &walk(&1, mode, where, &2))
  end

  defp walk({a, b}, mode, where, acc) do
    acc = walk(a, mode, where, acc)
    walk(b, mode, where, acc)
  end

  defp walk(list, mode, where, acc) when is_list(list),
    do: Enum.reduce(list, acc, &walk(&1, mode, where, &2))

  # A call/var node. Its FORM is the rule's own Elixir (`if`, `==`, `and`), never
  # code the rule emits, so it is deliberately not an occurrence.
  defp walk({form, _meta, args}, mode, where, acc) when is_list(args) do
    acc = if is_atom(form), do: acc, else: walk(form, mode, where, acc)
    Enum.reduce(args, acc, &walk(&1, mode, where, &2))
  end

  defp walk({form, _meta, ctx}, mode, where, acc) when is_atom(ctx) do
    if is_atom(form), do: acc, else: walk(form, mode, where, acc)
  end

  defp walk(atom, _mode, where, acc) when is_atom(atom),
    do: maybe_atom_ref(atom, [], where, acc)

  defp walk(str, mode, where, acc) when is_binary(str),
    do: code_string([str], 0, mode, where, acc)

  defp walk(_other, _mode, _where, acc), do: acc

  defp walk_blocks(blocks, arrow_mode, where, acc) do
    blocks
    |> List.flatten()
    |> Enum.reduce(acc, fn
      {key, body}, a when key in [:do, :else, :rescue, :catch, :after] ->
        clauses(body, arrow_mode, where, a)

      other, a ->
        walk(other, :expr, where, a)
    end)
  end

  defp clauses(body, arrow_mode, where, acc) when is_list(body),
    do: Enum.reduce(body, acc, &arrow(&1, arrow_mode, where, &2))

  defp clauses(body, _arrow_mode, where, acc), do: walk(body, :expr, where, acc)

  defp arrow({:->, _, [heads, body]}, arrow_mode, where, acc) do
    acc = Enum.reduce(List.wrap(heads), acc, &walk(&1, arrow_mode, where, &2))
    walk(body, :expr, where, acc)
  end

  defp arrow(other, _arrow_mode, where, acc), do: walk(other, :expr, where, acc)

  # --- occurrence recording ----------------------------------------------------

  # `{:/, _, [_, arity]}` is function-capture arity, not division — the exact false
  # positive the meta-test's allowlist calls out four times ("the `/` is capture
  # arity, not division").
  defp record_tuple(head, node, meta, mode, where, acc) when is_atom(head) do
    cond do
      head not in @constructs -> acc
      head == :/ and capture_arity?(node) -> acc
      true -> [occurrence(head, kind(mode), where, meta) | acc]
    end
  end

  defp record_tuple(_head, _node, _meta, _mode, _where, acc), do: acc

  defp capture_arity?({:{}, _, [:/, _, args]}) do
    case args do
      [_fun, arity] when is_integer(arity) -> true
      _ -> false
    end
  end

  defp capture_arity?(_), do: false

  # Skip a capture spec's `/` head — it is arity, not division — while still
  # walking its operands, which can hold constructs of their own.
  defp walk_capture_spec({:{}, _, [:/, m, args]}, mode, where, acc) do
    acc = walk(m, mode, where, acc)
    walk(args, mode, where, acc)
  end

  defp walk_capture_spec(other, mode, where, acc), do: walk(other, mode, where, acc)

  defp kind(:pattern), do: :match
  defp kind(_), do: :build

  defp occurrence(construct, kind, where, meta) do
    %{construct: construct, kind: kind, where: where, line: Keyword.get(meta, :line, 0)}
  end

  # A bare construct atom used as a VALUE: `when op in [:==, :!=]`, `[:if, :unless]`.
  defp maybe_atom_ref(atom, meta, where, acc) do
    if atom in @constructs, do: [occurrence(atom, :atom_ref, where, meta) | acc], else: acc
  end

  # A `quote do ... end` in fix code emits whatever it contains, literally — so
  # here a construct in call-form position IS emitted code.
  defp quoted_constructs(blocks, meta, where, acc) do
    line = Keyword.get(meta, :line, 0)

    {_n, found} =
      Macro.prewalk(blocks, [], fn
        {form, m, args} = n, a when is_atom(form) and is_list(args) ->
          if form in @constructs,
            do: {n, [occurrence(form, :build, where, Keyword.put(m, :line, line)) | a]},
            else: {n, a}

        n, a ->
          {n, a}
      end)

    found ++ acc
  end

  # A replacement string that carries a reinterpreted construct. Rather than
  # regex-matching English prose (a rule message like "`if/else` is redundant"
  # would match `if`, `and`, `or`, `in` …), the string is reassembled with
  # interpolations replaced by a placeholder variable and re-parsed as Elixir:
  # only a string that IS code, and whose code contains a construct in call/operator
  # position, counts. Prose does not parse, so it contributes nothing.
  defp code_string(parts, line, mode, where, acc) do
    text =
      Enum.map_join(parts, fn
        b when is_binary(b) -> b
        _ -> "__credence_hole__"
      end)

    case Code.string_to_quoted(text) do
      {:ok, ast} ->
        {_n, found} =
          Macro.prewalk(ast, [], fn
            {form, m, args} = n, a when is_atom(form) and is_list(args) ->
              if form in @constructs and not capture_slash?(form, args),
                do:
                  {n,
                   [occurrence(form, string_kind(mode), where, Keyword.put(m, :line, line)) | a]},
                else: {n, a}

            n, a ->
              {n, a}
          end)

        found ++ acc

      _ ->
        acc
    end
  end

  defp capture_slash?(:/, [_, arity]) when is_integer(arity), do: true
  defp capture_slash?(_form, _args), do: false

  defp string_kind(:pattern), do: :match
  defp string_kind(_), do: :build_str

  # --- matcher clauses and anchoring -------------------------------------------

  # Every clause head in fix-reachable code that destructures a construct-bearing
  # AST node, with whether that head is ANCHORED — i.e. pins the match to a shape
  # no DSL expression can contain (a definition form, a module-level construct, or
  # a call into a module the DSL grammars have no translation for).
  defp matcher_group({:__patterns__, _, args}, where) when is_list(args),
    do: clause_entry(args, where)

  defp matcher_group(node, where) do
    {_n, groups} =
      Macro.prewalk(node, [], fn
        {:fn, _, clauses} = n, a when is_list(clauses) ->
          {n, a ++ [heads_of(clauses, where)]}

        {:case, _, [_subject | blocks]} = n, a ->
          {n, a ++ [block_heads(blocks, where)]}

        n, a ->
          {n, a}
      end)

    # `Macro.prewalk` visits outer nodes first, so the first non-empty group is
    # the outermost matcher in this function body.
    Enum.find(groups, [], &(&1 != []))
  end

  defp heads_of(clauses, where) do
    Enum.flat_map(clauses, fn
      {:->, _, [heads, _body]} -> clause_entry(List.wrap(heads), where)
      _ -> []
    end)
  end

  defp block_heads(blocks, where) do
    blocks
    |> List.flatten()
    |> Enum.flat_map(fn
      {key, clauses} when key in [:do, :else] and is_list(clauses) -> heads_of(clauses, where)
      _ -> []
    end)
  end

  # Only clause heads that actually destructure an AST node matter — a head like
  # `node ->`, `{:ok, x} ->` or `_ ->` selects nothing and is not a matcher.
  defp clause_entry(heads, where) do
    if node_literal?(heads) do
      [%{where: where, anchored: anchored?(heads), head: Macro.to_string(heads)}]
    else
      []
    end
  end

  # Whether a clause head destructures an **AST node** rather than some ordinary
  # 3-tuple. `{:ok, patch, lines}` is a result tuple, not a matcher; `{:if, _meta,
  # [c, cl]}` is. The discriminators, in order:
  #
  #   * the callee slot is a `{:., …}` / `{:__aliases__, …}` literal — a qualified
  #     call node, unambiguous; or
  #   * the metadata slot is `_`, `_foo`, or a variable named `meta`/`m` — the
  #     idiomatic "I don't care about metadata" spelling; or
  #   * the callee slot is an atom literal AND the args slot is a list literal or
  #     `_` — `{:if, m, _}`, `{:length, _, [arg]}`.
  defp node_literal?(heads) do
    {_n, hit} =
      Macro.prewalk(heads, false, fn
        {:{}, _, [callee, meta, args]} = n, a -> {n, a or ast_node_shape?(callee, meta, args)}
        n, a -> {n, a}
      end)

    hit
  end

  defp ast_node_shape?(callee, meta, args) do
    qualified_callee?(callee) or meta_slot?(meta) or
      (is_atom(callee) and (is_list(args) or underscore?(args)))
  end

  defp qualified_callee?({:{}, _, [{:., _, _} | _]}), do: true
  defp qualified_callee?({:., _, _}), do: true
  defp qualified_callee?({:{}, _, [{:__aliases__, _, _} | _]}), do: true
  defp qualified_callee?({:__aliases__, _, _}), do: true
  defp qualified_callee?(_), do: false

  defp meta_slot?({name, _, ctx}) when is_atom(name) and is_atom(ctx) do
    s = Atom.to_string(name)
    String.starts_with?(s, "_") or s in ["meta", "m"]
  end

  defp meta_slot?(_), do: false

  defp underscore?({:_, _, ctx}) when is_atom(ctx), do: true
  defp underscore?(_), do: false

  defp anchored?(heads) do
    {_n, hit} =
      Macro.prewalk(heads, false, fn
        {:__aliases__, _, [mod]} = n, a when is_atom(mod) ->
          {n, a or mod in @plain_only_modules}

        atom, acc when is_atom(atom) ->
          {atom, acc or atom in @def_anchors}

        n, a ->
          {n, a}
      end)

    hit
  end
end
