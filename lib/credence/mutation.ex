defmodule Credence.Mutation do
  @moduledoc """
  Deterministic first-order **semantic mutants** of a rule implementation
  (docs/12 C18, stage 1 — report only).

  A mutant is one byte-level edit to one token of the rule's source. Run the
  rule's own test triplet against the mutant: if the triplet still passes, the
  mutant **survived** — a behaviour change the tests never noticed. The per-rule
  kill rate (killed / valid mutants) is a tightness score for the triplet, not a
  correctness score for the rule.

  ## The operator set

  Exactly the four families docs/12 C18 names, ported from the sibling dataset
  repo's `semantic_mutants/2`:

    * `:comparison_swap` — `<`↔`<=`, `>`↔`>=`, both as operators (`a >= b`) and
      as atom literals (`op in [:>=, :<=]`). Strict↔non-strict is the swap that
      matters here: half this ruleset's matchers turn on exactly that boundary
      (`NoManualMax` flags `>=` and deliberately refuses `>`).
    * `:off_by_one` — every integer literal, ±1, as two mutants.
    * `:ok_error_swap` — `:ok`↔`:error` atom literals. `check_node/1` and
      `try_fix_*/2` in this codebase signal "matched"/"did not match" with
      exactly this pair, so the swap inverts a matcher wholesale.
    * `:boolean_flip` — `true`↔`false` literals.

  ## What is *not* mutated, and why

  Mutation is scoped to tokens that lie inside a `def`/`defp`/`defmacro`/
  `defmacrop` source range, or inside a non-metadata module attribute
  (`@comparison_ops`, `@max_passes`, `@window_lines`, …). Everything else is
  excluded:

    * **`@moduledoc`, `@doc`, comments** — prose. Mutating `>= ` inside a
      moduledoc table changes no behaviour and would be an equivalent mutant by
      construction, ~40% of the token budget on some rules.
    * **`@impl`, `@spec`, `@type`, `@behaviour`, `@callback`** — declarations.
    * **`@priority`** — pipeline *ordering* metadata. The triplet calls
      `rule.check/2` and `RuleHelpers.apply_rule_fix/3` directly and never runs
      the pipeline, so a priority mutant is a guaranteed survivor that says
      nothing about the triplet. Excluding it keeps it out of the tail list.
    * **string and charlist contents** — the tokenizer hands back a whole
      `bin_string`/heredoc as one token, so an interior `>=` is unreachable.
      Message text is not behaviour.
    * **capture placeholders and capture arities** — the `1` of `&1` tokenizes
      as `capture_int` + `int`, and the `1` of `&strip_meta/1` is a function
      arity. `&0` does not compile, `&strip_meta/2` names a function that does
      not exist, and `&2` silently changes a capture's arity; none is a mutant
      of the rule's logic. Both are skipped — the first by token lookback, the
      second by collecting the arity literals' positions from the AST.

  ## Determinism and the cap

  Mutants are emitted in source order (line, column, operator, replacement) and
  the generator is a pure function of the source text — same file in, same list
  out, every run. Above `cap` (default 40, the dataset's number) the list is
  down-sampled by round-robining the operator families in source order, so a
  file with 300 integer literals still spends part of its budget on its four
  comparison operators.

  ## Equivalent mutants

  Some survivors are *equivalent* mutants — the edit provably cannot change
  behaviour, so no test could have caught it. docs/14 E6 hit one on its first
  four hand-made mutants (`NoManualMax`'s operator guard admits `:<`, but every
  downstream clause rejects strict forms, making the guard breadth dead code).
  There is no automated oracle for this, which is exactly why C18 stage 1 is
  report-only: every survivor row carries file, line, column, before→after and
  the verbatim source line so triage is a read, not a re-derivation.
  """

  defmodule Mutant do
    @moduledoc """
    One first-order edit: replace `original` with `replacement` at
    `line`/`column` (1-based, codepoint columns, as the Elixir tokenizer reports
    them). `context` is the verbatim source line, carried for triage.
    """

    @type operator :: :comparison_swap | :off_by_one | :ok_error_swap | :boolean_flip

    @type t :: %__MODULE__{
            id: String.t(),
            operator: operator(),
            line: pos_integer(),
            column: pos_integer(),
            original: String.t(),
            replacement: String.t(),
            context: String.t()
          }

    defstruct [:id, :operator, :line, :column, :original, :replacement, :context]
  end

  @default_cap 40

  # Module attributes whose contents are declarations or prose, not behaviour
  # the rule's own triplet can observe. See the moduledoc for the reasoning on
  # `:priority` in particular.
  @metadata_attributes ~w(
    moduledoc doc typedoc shortdoc impl spec type typep opaque callback
    macrocallback behaviour behavior derive enforce_keys deprecated dialyzer
    compile external_resource priority tag moduletag describetag
  )a

  @definitions ~w(def defp defmacro defmacrop)a

  @comparison_swaps %{:< => :<=, :<= => :<, :> => :>=, :>= => :>}

  # Emission order within a source position, and the round-robin order used when
  # the cap bites. Comparison first because it is the family this ruleset's
  # matchers actually turn on.
  @operator_order [:comparison_swap, :ok_error_swap, :boolean_flip, :off_by_one]

  @doc """
  Generate the deterministic first-order mutants of `source`.

  Options:

    * `:cap` — maximum mutants returned (default `#{@default_cap}`). `:infinity`
      disables the cap.
    * `:id_prefix` — string prefixed to each mutant id (the sweep passes the
      rule's snake name).

  Returns `{:ok, [Mutant.t()]}`, or `{:error, reason}` when `source` does not
  parse or does not tokenize.
  """
  @spec mutants(String.t(), keyword()) :: {:ok, [Mutant.t()]} | {:error, term()}
  def mutants(source, opts \\ []) when is_binary(source) do
    cap = Keyword.get(opts, :cap, @default_cap)
    prefix = Keyword.get(opts, :id_prefix, "")

    with {:ok, ast} <- parse(source),
         {:ok, tokens} <- tokenize(source) do
      ranges = mutable_ranges(ast)
      arities = capture_arity_positions(ast)
      lines = String.split(source, "\n")

      mutants =
        tokens
        |> with_previous()
        |> Enum.filter(fn {token, _prev} ->
          in_any_range?(token, ranges) and position(token) not in arities
        end)
        |> Enum.flat_map(fn {token, prev} -> token_mutants(token, prev, lines, prefix) end)
        |> Enum.sort_by(&sort_key/1)
        |> apply_cap(cap)

      {:ok, mutants}
    end
  end

  @doc """
  Apply `mutant` to `source`, returning the mutated source.

  Raises `ArgumentError` if the text at the mutant's position is not
  `mutant.original` — a misalignment between the tokenizer's columns and the
  bytes must fail loudly, never silently corrupt a different token and get
  scored as a mutation result.
  """
  @spec apply_mutant(String.t(), Mutant.t()) :: String.t()
  def apply_mutant(source, %Mutant{} = mutant) do
    lines = String.split(source, "\n")

    {before_lines, [line | after_lines]} =
      case Enum.split(lines, mutant.line - 1) do
        {_, []} -> raise ArgumentError, "mutant line #{mutant.line} past end of source"
        split -> split
      end

    original = String.to_charlist(mutant.original)
    {lead, rest} = Enum.split(String.to_charlist(line), mutant.column - 1)
    {found, trail} = Enum.split(rest, length(original))

    if found != original do
      raise ArgumentError,
            "mutant #{mutant.id} expected #{inspect(mutant.original)} at " <>
              "#{mutant.line}:#{mutant.column}, found #{inspect(List.to_string(found))}"
    end

    mutated = List.to_string(lead) <> mutant.replacement <> List.to_string(trail)
    Enum.join(before_lines ++ [mutated] ++ after_lines, "\n")
  end

  @doc "The operator families this generator emits, in emission order."
  @spec operators() :: [Mutant.operator()]
  def operators, do: @operator_order

  @doc "The default per-subject mutant cap."
  @spec default_cap() :: pos_integer()
  def default_cap, do: @default_cap

  # --- scoping -------------------------------------------------------------

  defp parse(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} -> {:ok, ast}
      {:error, reason} -> {:error, {:parse_error, reason}}
    end
  end

  # Source ranges in which a token is considered part of the implementation.
  defp mutable_ranges(ast) do
    {_ast, ranges} = Macro.prewalk(ast, [], &collect_range/2)
    Enum.reverse(ranges)
  end

  # `{line, column}` of every `N` in a `&fun/N` / `&Mod.fun/N` capture. Mutating
  # one names a function that does not exist — an invalid mutant, not a
  # behaviour change, and it would otherwise eat cap budget.
  defp capture_arity_positions(ast) do
    {_ast, positions} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:&, _, [{:/, _, [_fun, {:__block__, meta, [arity]}]}]} = node, acc
        when is_integer(arity) ->
          case {Keyword.get(meta, :line), Keyword.get(meta, :column)} do
            {line, column} when is_integer(line) and is_integer(column) ->
              {node, MapSet.put(acc, {line, column})}

            _ ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    positions
  end

  defp collect_range({definition, _meta, [_ | _]} = node, acc) when definition in @definitions do
    {node, prepend_range(node, acc)}
  end

  defp collect_range({:@, _meta, [{name, _, [_value]}]} = node, acc)
       when is_atom(name) do
    if name in @metadata_attributes, do: {node, acc}, else: {node, prepend_range(node, acc)}
  end

  defp collect_range(node, acc), do: {node, acc}

  defp prepend_range(node, acc) do
    case Sourceror.get_range(node) do
      %{start: [line: sl, column: sc], end: [line: el, column: ec]} ->
        [{{sl, sc}, {el, ec}} | acc]

      _ ->
        acc
    end
  end

  defp in_any_range?(token, ranges) do
    position = position(token)
    Enum.any?(ranges, fn {start, stop} -> position >= start and position < stop end)
  end

  # --- tokenizing ----------------------------------------------------------

  defp tokenize(source) do
    # `:elixir_tokenizer.tokenize/3` returns the token list at element 4 in
    # every Elixir this project supports (5-tuple pre-1.19, 6-tuple after), in
    # REVERSE source order.
    case :elixir_tokenizer.tokenize(String.to_charlist(source), 1, []) do
      result when is_tuple(result) and elem(result, 0) == :ok ->
        {:ok, result |> elem(4) |> Enum.reverse()}

      other ->
        {:error, {:tokenize_error, other}}
    end
  end

  defp with_previous(tokens), do: Enum.zip(tokens, [nil | tokens])

  defp position({_type, {line, column, _extra}}), do: {line, column}
  defp position({_type, {line, column, _extra}, _value}), do: {line, column}
  defp position({_type, {line, column, _extra}, _value, _rest}), do: {line, column}
  defp position(_), do: {0, 0}

  # --- the four operator families -----------------------------------------

  # `a >= b` — the operator itself.
  defp token_mutants({:rel_op, _pos, op} = token, _prev, lines, prefix)
       when is_map_key(@comparison_swaps, op) do
    swapped = @comparison_swaps[op]
    [build(token, :comparison_swap, to_string(op), to_string(swapped), lines, prefix)]
  end

  # `op in [:>=, :<=]` — the operator as an atom literal.
  defp token_mutants({:atom, _pos, op} = token, _prev, lines, prefix)
       when is_map_key(@comparison_swaps, op) do
    swapped = @comparison_swaps[op]

    [
      build(
        token,
        :comparison_swap,
        ":" <> to_string(op),
        ":" <> to_string(swapped),
        lines,
        prefix
      )
    ]
  end

  defp token_mutants({:atom, _pos, :ok} = token, _prev, lines, prefix) do
    [build(token, :ok_error_swap, ":ok", ":error", lines, prefix)]
  end

  defp token_mutants({:atom, _pos, :error} = token, _prev, lines, prefix) do
    [build(token, :ok_error_swap, ":error", ":ok", lines, prefix)]
  end

  defp token_mutants({true, _pos} = token, _prev, lines, prefix) do
    [build(token, :boolean_flip, "true", "false", lines, prefix)]
  end

  defp token_mutants({false, _pos} = token, _prev, lines, prefix) do
    [build(token, :boolean_flip, "false", "true", lines, prefix)]
  end

  # The `1` of a `&1` capture placeholder is not an integer literal of the rule's
  # logic: `&0` does not compile and `&2` changes the capture's arity.
  defp token_mutants({:int, _pos, _text}, {:capture_int, _, _}, _lines, _prefix), do: []

  defp token_mutants({:int, {_line, _column, value}, text} = token, _prev, lines, prefix)
       when is_integer(value) do
    original = List.to_string(text)

    [
      build(token, :off_by_one, original, Integer.to_string(value + 1), lines, prefix),
      build(token, :off_by_one, original, Integer.to_string(value - 1), lines, prefix)
    ]
  end

  defp token_mutants(_token, _prev, _lines, _prefix), do: []

  defp build(token, operator, original, replacement, lines, prefix) do
    {line, column} = position(token)

    %Mutant{
      id: "#{prefix}#{line}:#{column}:#{operator}:#{original}->#{replacement}",
      operator: operator,
      line: line,
      column: column,
      original: original,
      replacement: replacement,
      context: Enum.at(lines, line - 1, "")
    }
  end

  # --- ordering and cap ----------------------------------------------------

  defp sort_key(%Mutant{} = m) do
    {m.line, m.column, Enum.find_index(@operator_order, &(&1 == m.operator)), m.replacement}
  end

  defp apply_cap(mutants, :infinity), do: mutants

  defp apply_cap(mutants, cap) when is_integer(cap) and cap > 0 do
    if length(mutants) <= cap do
      mutants
    else
      mutants
      |> Enum.group_by(& &1.operator)
      |> then(fn grouped -> Enum.map(@operator_order, &Map.get(grouped, &1, [])) end)
      |> interleave()
      |> Enum.take(cap)
      |> Enum.sort_by(&sort_key/1)
    end
  end

  # Round-robin the families so the cap never spends the whole budget on the one
  # family that happens to be most frequent in a file.
  defp interleave(lists) do
    case Enum.reject(lists, &(&1 == [])) do
      [] ->
        []

      remaining ->
        heads = Enum.map(remaining, &hd/1)
        tails = Enum.map(remaining, &tl/1)
        heads ++ interleave(tails)
    end
  end
end
