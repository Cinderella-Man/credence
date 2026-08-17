defmodule Credence.Pattern.PreferErlangFloat do
  @moduledoc """
  Replaces float-coercion arithmetic tricks with explicit `:erlang.float/1`.

  LLMs (and developers) use `x * 1.0`, `x / 1.0`, `x + 0.0`, or `x - 0.0` to
  coerce a number to a float. These are arithmetic idioms borrowed from Python;
  `:erlang.float/1` expresses the same intent explicitly and works whether the
  input is an integer (converts) or already a float (returns it unchanged).

  The rewrite **preserves the float result** — it does not delete the coercion.
  Deleting `* 1.0` (an earlier mistake of a now-merged sibling rule) would turn
  `6.0` back into `6`, a value-kind change; wrapping in `:erlang.float/1` keeps
  the value identical for every number.

  Applies to **any operand shape** — bare variables (`n * 1.0`) and compound
  expressions alike (`Enum.sum(list) * 1.0`, `(a + b) * 1.0`).

  ## Detected patterns

      x * 1.0      1.0 * x
      x / 1.0
      x + 0.0      0.0 + x
      x - 0.0

  Note: `0.0 - x` is NOT flagged — it negates, not coerces.

  ## Behaviour note

  For every numeric operand the rewrite is exact (same float value). A
  *non-number* operand raises in both forms — `x * 1.0` raises `ArithmeticError`
  while `:erlang.float(x)` raises `ArgumentError` — so the code crashes either
  way and only the exception module differs. (A non-number operand at a
  float-coercion site is already-broken code.)

  ## Taste review, on real corpus sites (2026-08-17)

  D4 asked whether this rule's suggestions are *good taste* on hand-written code, not
  just correct. Four accepted findings were pulled from the corpus and run through
  `fix/2`. All four rewrote correctly; the one that decides the question is `archethic`:

      # the `0.0 + x` is used to cast integers to floats
      lhs = Decimal.from_float(0.0 + lhs)

  The author wrote a **comment to explain the idiom**. That is the rule's whole thesis,
  found in the wild rather than argued: `Decimal.from_float(:erlang.float(lhs))` needs no
  comment. (The rewrite does leave that comment describing a spelling that is gone. It
  still states the intent correctly, so this is staleness rather than a defect — but it is
  the one cosmetic cost on record.)

  The least comfortable site was `cldr_utils`, where the coercion is the tail of a
  multiplication chain rather than applied to one operand:

      Integer.undigits(digits) * power_of_10(place - length(digits)) * sign * 1.0
      :erlang.float(Integer.undigits(digits) * power_of_10(place - length(digits)) * sign)

  The whole chain has to be wrapped, which is a bigger visual change than the other
  three. Executed on both a float-valued and an integer-valued chain, the results are
  `===` identical — including the float-ness that the `* 1.0` was there to produce, which
  is the thing a careless rewrite would drop.

  Verdict: **keep as is.** The suggestion reads at least as well as the original at every
  site sampled, and better at two of four.

  ## Bad

      defp to_float(n) when is_integer(n), do: n * 1.0
      avg = total / count * 1.0

  ## Good

      defp to_float(n) when is_integer(n), do: :erlang.float(n)
      avg = :erlang.float(total / count)
  """

  use Credence.Pattern.Rule

  # DSL-unsafe in Ash.Expr / Ecto.Query: replaces float-coercion arithmetic
  # (`x * 1.0`, `x / 1.0`) with `:erlang.float/1`. A bare Erlang call is not a
  # query operator — Ash will not translate it and Ecto forbids it — whereas the
  # original arithmetic maps to SQL. Nx.Defn is NOT listed because this rule
  # handles it more precisely with its own `defn_operator_positions/1` guard:
  # inside a `defn`/`defnp` body `x * 1.0` is valid *element-wise* tensor math, so
  # the guard skips those operator positions outright (an `unsafe_in_dsl :nx_defn`
  # gate keys on the same `defn` blocks and would be redundant). Outside a defn
  # body operators are plain `Kernel.*` — exact on numbers, already-crashing on a
  # tensor — so no working defn code is silently changed.
  @impl true
  def unsafe_in_dsl, do: [:ash_expr, :ecto_query]
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    if overrides_arith_operators?(ast) do
      []
    else
      defn_ops = defn_operator_positions(ast)

      {_ast, issues} =
        Macro.prewalk(ast, [], fn
          {op, meta, [left, right]} = node, acc
          when op in [:*, :/, :+, :-] ->
            cond do
              MapSet.member?(defn_ops, position(meta)) ->
                {node, acc}

              # operand OP identity (right-hand identity)
              identity_right?(op, unwrap_float(right)) ->
                {node, [build_issue(meta) | acc]}

              # identity OP operand (left-hand identity, commutative ops only)
              op in [:*, :+] and identity_left?(op, unwrap_float(left)) ->
                {node, [build_issue(meta) | acc]}

              true ->
                {node, acc}
            end

          node, acc ->
            {node, acc}
        end)

      Enum.reverse(issues)
    end
  end

  @impl true
  def fix_patches(ast, _opts) do
    if overrides_arith_operators?(ast) do
      []
    else
      defn_ops = defn_operator_positions(ast)
      Credence.RuleHelpers.patches_from_postwalk(ast, &maybe_to_erlang_float(&1, defn_ops))
    end
  end

  # `* 1.0` / `/ 1.0` are float coercion ONLY when `*`//` are the Kernel
  # operators on numbers. They are not when:
  #
  #  - the module overrides arithmetic operators (`use Image.Math`,
  #    `import Kernel, except: [*: 2]`) — every `*` is then a struct/image
  #    operation, and `:erlang.float/1` on that struct crashes; OR
  #  - the operand is an Nx tensor inside a `defn`/`defnp` body — `:erlang.float/1`
  #    is a raw BIF outside the defn-allowed function set.
  #
  # The first is module-wide (skip the whole file); the second is per operator
  # node (regular `def`s in the same module are still fair game).
  defp overrides_arith_operators?(ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        _node, true ->
          {nil, true}

        {:use, _, [{:__aliases__, _, parts} | _]} = node, _
        when is_list(parts) and parts != [] ->
          {node, List.last(parts) == :Math}

        {:import, _, [{:__aliases__, _, [:Kernel]} | rest]} = node, _ ->
          {node, mentions_arith_op?(rest)}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp mentions_arith_op?(ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        _node, true -> {nil, true}
        op, _ when op in [:*, :/, :+, :-] -> {op, true}
        node, acc -> {node, acc}
      end)

    found
  end

  defp defn_operator_positions(ast) do
    {_ast, set} =
      Macro.prewalk(ast, MapSet.new(), fn
        {defn, _, _} = node, acc when defn in [:defn, :defnp] ->
          {_n, inner} =
            Macro.prewalk(node, acc, fn
              {op, meta, [_l, _r]} = n, a when op in [:*, :/, :+, :-] ->
                {n, MapSet.put(a, position(meta))}

              n, a ->
                {n, a}
            end)

          {node, inner}

        node, acc ->
          {node, acc}
      end)

    set
  end

  defp position(meta), do: {Keyword.get(meta, :line), Keyword.get(meta, :column)}

  # Replace identity-coercion arithmetic with `:erlang.float(operand)`, where the
  # operand is whichever side is not the `1.0` / `0.0` identity literal.
  defp maybe_to_erlang_float({op, meta, [left, right]} = node, defn_ops)
       when op in [:*, :/, :+, :-] do
    cond do
      MapSet.member?(defn_ops, position(meta)) ->
        node

      identity_right?(op, unwrap_float(right)) ->
        erlang_float(unwrap_block(left))

      op in [:*, :+] and identity_left?(op, unwrap_float(left)) ->
        erlang_float(unwrap_block(right))

      true ->
        node
    end
  end

  defp maybe_to_erlang_float(node, _defn_ops), do: node

  # Strip a single Sourceror `{:__block__, _, [inner]}` wrapper (around a bare
  # variable or literal); leave compound expression nodes untouched.
  defp unwrap_block({:__block__, _, [inner]}), do: inner
  defp unwrap_block(node), do: node

  defp erlang_float(operand_node) do
    {{:., [], [:erlang, :float]}, [], [operand_node]}
  end

  defp identity_right?(:*, 1.0), do: true
  defp identity_right?(:/, 1.0), do: true
  defp identity_right?(:+, +0.0), do: true
  defp identity_right?(:-, +0.0), do: true
  defp identity_right?(_, _), do: false

  defp identity_left?(:*, 1.0), do: true
  defp identity_left?(:+, +0.0), do: true
  defp identity_left?(_, _), do: false

  # Sourceror wraps float literals in {:__block__, meta, [value]}.
  defp unwrap_float({:__block__, _, [val]}) when is_float(val), do: val
  defp unwrap_float(_), do: nil

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_erlang_float,
      message:
        "Use `:erlang.float(x)` for number → float coercion instead of " <>
          "arithmetic identity tricks (`* 1.0`, `/ 1.0`, `+ 0.0`, `- 0.0`).",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
