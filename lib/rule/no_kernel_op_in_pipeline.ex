defmodule Credence.Rule.NoKernelOpInPipeline do
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

  use Credence.Rule
  alias Credence.Issue

  @flagged_ops ~w(== != === !== < > <= >= and or)a

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:|>, _, [_lhs, {{:., _, [{:__aliases__, _, [:Kernel]}, op]}, meta, [_arg]}]} = node,
        acc
        when op in @flagged_ops ->
          {node, [build_issue(meta, op) | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    ast = Sourceror.parse_string!(source)

    if has_flagged_kernel_op?(ast) do
      ast
      |> Macro.postwalk(fn
        {:|>, _meta,
         [lhs, {{:., _, [{:__aliases__, _, [:Kernel]}, op]}, _, [arg]}]}
        when op in @flagged_ops ->
          transform_kernel_pipe(lhs, op, arg)

        node ->
          node
      end)
      |> Sourceror.to_string()
    else
      source
    end
  end

  defp has_flagged_kernel_op?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:|>, _, [_lhs, {{:., _, [{:__aliases__, _, [:Kernel]}, op]}, _, [_arg]}]} = node,
        _acc
        when op in @flagged_ops ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found?
  end

  # ── Transform logic ─────────────────────────────────────────────

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

  # ── Issue building ──────────────────────────────────────────────

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
