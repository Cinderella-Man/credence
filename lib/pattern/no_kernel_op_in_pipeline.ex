defmodule Credence.Pattern.NoKernelOpInPipeline do
  @moduledoc """
  Detects qualified `Kernel.op/2` calls used as steps in a pipeline.

  LLMs produce code like `list |> Enum.sort() |> Kernel.==(list)` because
  they try to keep everything in one pipeline. In Elixir, comparison and
  boolean operators are used in infix position, not as qualified calls.

  ## Bad

      list |> Enum.uniq() |> Enum.sort() |> Kernel.==(list)

      score |> calculate() |> Kernel.>=(threshold)

  ## Good

      (list |> Enum.uniq() |> Enum.sort()) == list

      calculate(score) >= threshold

  ## Auto-fix

  Extracts the operator from the pipeline and restructures:

  - **0 remaining steps**: `x |> Kernel.op(y)` → `x op y`
  - **1 remaining step**: `x |> f() |> Kernel.op(y)` → `f(x) op y`
  - **2+ remaining steps**: `x |> f() |> g() |> Kernel.op(y)` → `(x |> f() |> g()) op y`

  Arithmetic operators (`+`, `-`, `*`, `/`) are not flagged since
  `Kernel.+(n)` in a pipe has no clearly better alternative.
  """

  use Credence.Pattern.Rule

  # DSL-unsafe: turns `x |> Kernel.op(y)` into the infix `x op y`; inside Ash.Expr,
  # Ecto.Query and Nx.Defn those operators are reinterpreted (or `Kernel.*` is
  # forbidden), so the rewrite changes meaning.
  @impl true
  def unsafe_in_dsl, do: :all
  alias Credence.Issue
  alias Credence.RuleHelpers

  @flagged_ops ~w(== != === !== < > <= >= and or)a

  @impl true
  def check(ast, _opts) do
    consumed = consumed_by_pipe_positions(ast)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:|>, pipe_meta, [lhs, {{:., _, [{:__aliases__, _, [:Kernel]}, op]}, meta, [_arg]}]} =
            node,
        acc
        when op in @flagged_ops ->
          if unsafe_to_flatten?(node, lhs, pipe_meta, consumed) do
            {node, acc}
          else
            {node, [build_issue(meta, op) | acc]}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    consumed = consumed_by_pipe_positions(ast)

    RuleHelpers.patches_from_postwalk(ast, fn
      {:|>, pipe_meta, [lhs, {{:., _, [{:__aliases__, _, [:Kernel]}, op]}, _, [arg]}]} = node
      when op in @flagged_ops ->
        if unsafe_to_flatten?(node, lhs, pipe_meta, consumed) do
          node
        else
          transform_kernel_pipe(lhs, op, arg)
        end

      node ->
        node
    end)
  end

  # A `Kernel.op` pipe step must NOT be flattened to infix when:
  #
  # 1. it is itself the LHS of a further `|>`. `|>` binds tighter than every
  #    flagged operator, so `(a op b) |> rest` re-parses as `a op (b |> rest)` —
  #    a precedence flip that changes meaning and usually crashes downstream.
  #
  # 2. it is a quoted macro fragment destined to be spliced INTO a pipe: its LHS
  #    is a zero-arity call (`Enum.count()`, no upstream value yet) and it
  #    contains an `unquote`. Flattening yields `upstream |> (Enum.count() == x)`,
  #    which fails at macro expansion (cannot pipe into a binary operator). The
  #    `unquote` + upstream-less head together mark this fragment.
  defp unsafe_to_flatten?(node, lhs, pipe_meta, unsafe) do
    MapSet.member?(unsafe, position(pipe_meta)) or
      (zero_arity_call?(lhs) and contains_unquote?(node))
  end

  # Positions of `Kernel.op` pipe steps that cannot be safely flattened to infix
  # because they are consumed by a pipe step that REMAINS a pipe after the fix.
  #
  # A whole chain of flagged Kernel ops (`a |> Kernel.==(b) |> Kernel.or(c)`)
  # flattens together to `a == b or c`, so none is unsafe. But the moment a
  # non-flagged step sits above an op in the chain (`a |> Kernel.<=(b) |> case`,
  # `a |> Kernel.>=(b) |> f.()`), that step stays a `|>`; since `|>` binds
  # tighter than every flagged operator, flattening the op below it re-parses
  # `(x op y) |> step` as `x op (y |> step)`. We propagate this "consumed by a
  # surviving pipe" context down the chain: it taints every op beneath the first
  # non-flagged step.
  defp consumed_by_pipe_positions(ast), do: collect_unsafe(ast, true, MapSet.new())

  # `ctx_safe?` — is an op-pipe at this position safe to flatten (i.e. NOT
  # consumed by a surviving pipe)? Only the lhs of a `|>` continues the chain;
  # everything else is an independent expression (fresh safe context).
  defp collect_unsafe({:|>, meta, [lhs, rhs]}, ctx_safe?, acc) do
    rhs_kernel? = flagged_kernel_op?(rhs)
    acc = if rhs_kernel? and not ctx_safe?, do: MapSet.put(acc, position(meta)), else: acc
    acc = collect_unsafe(lhs, ctx_safe? and rhs_kernel?, acc)
    collect_unsafe(rhs, true, acc)
  end

  defp collect_unsafe({form, _meta, args}, _ctx, acc) when is_list(args) do
    acc = collect_unsafe(form, true, acc)
    Enum.reduce(args, acc, &collect_unsafe(&1, true, &2))
  end

  defp collect_unsafe({a, b}, _ctx, acc) do
    collect_unsafe(b, true, collect_unsafe(a, true, acc))
  end

  defp collect_unsafe(list, _ctx, acc) when is_list(list) do
    Enum.reduce(list, acc, &collect_unsafe(&1, true, &2))
  end

  defp collect_unsafe(_leaf, _ctx, acc), do: acc

  defp flagged_kernel_op?({{:., _, [{:__aliases__, _, [:Kernel]}, op]}, _, [_arg]})
       when op in @flagged_ops,
       do: true

  defp flagged_kernel_op?(_), do: false

  defp position(meta), do: {Keyword.get(meta, :line), Keyword.get(meta, :column)}

  defp zero_arity_call?({fun, _meta, []}) when is_atom(fun), do: true
  defp zero_arity_call?({{:., _, _}, _meta, []}), do: true
  defp zero_arity_call?(_), do: false

  defp contains_unquote?(ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        _node, true -> {nil, true}
        {:unquote, _, _} = n, _ -> {n, true}
        node, acc -> {node, acc}
      end)

    found
  end

  defp transform_kernel_pipe(lhs, op, arg) do
    case count_pipes(lhs) do
      0 ->
        # x |> Kernel.op(y) → x op y
        {op, [], [lhs, arg]}

      1 ->
        # x |> f() |> Kernel.op(y) → f(x) op y
        {:|>, _, [initial, step]} = lhs
        inlined = inline_pipe_step(initial, step)
        {op, [], [inlined, arg]}

      _ ->
        # x |> f() |> g() |> Kernel.op(y) → (x |> f() |> g()) op y
        # Parens are implicit: |> has higher precedence than all flagged ops
        {op, [], [lhs, arg]}
    end
  end

  defp count_pipes({:|>, _, [lhs, _]}), do: 1 + count_pipes(lhs)
  defp count_pipes(_), do: 0

  # Inline: x |> func(args) → func(x, args)
  defp inline_pipe_step(input, {func_name, meta, args}) when is_atom(func_name) do
    {func_name, meta, [input | args || []]}
  end

  defp inline_pipe_step(input, {{:., dot_meta, qualified}, call_meta, args}) do
    {{:., dot_meta, qualified}, call_meta, [input | args || []]}
  end

  # Fallback: shouldn't happen, but keep as pipe to be safe
  defp inline_pipe_step(input, step) do
    {:|>, [], [input, step]}
  end

  defp build_issue(meta, op) do
    %Issue{
      rule: :no_kernel_op_in_pipeline,
      message: """
      Piping into `Kernel.#{op}/2` is non-idiomatic Elixir. Operators should \
      be used in infix position.

      Extract the comparison from the pipeline:

          result = pipeline
          result #{op} value
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
