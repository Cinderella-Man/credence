defmodule Credence.Semantic.NoPipeIntoUnaryArithmetic do
  @moduledoc """
  Rewrites `x |> + 1` into `x |> Kernel.+(1)`, which is what it was meant to be.

  The compiler both diagnoses this and dictates the repair:

      piping into a unary operator is not supported, please use the qualified
      name: Kernel.+(1), instead of +1

  `x |> + 1` looks like "add one to x" and is not. `+ 1` on the right of a pipe
  parses as **unary** plus applied to `1`, so there is no two-argument call for
  the pipe to feed, and the compile fails. The author meant `Kernel.+(x, 1)`,
  which is exactly what `x |> Kernel.+(1)` produces.

  ## Scope: `+` and `-` only, and deliberately

  Those are the two arithmetic operators with a unary form, so they are the two
  that get this far. `x |> * 2` and `x |> / 2` are **syntax** errors — the source
  does not parse at all — so they never reach a Semantic rule and belong to the
  Syntax round if anyone builds them.

  ## Equivalence

  The input does not compile, so there is no behaviour to preserve: any output
  that compiles is an improvement over a file that does not. What still has to
  hold is that the output means what the author wrote, and it does — the repair
  is the compiler's own suggested qualified form, with the operand carried over
  untouched, so `x |> Kernel.+(1)` is `Kernel.+(x, 1)` is `x + 1`.

  ## Bad

      defmodule PipeUnaryNPIUA do
        def bump(x), do: x |> + 1
      end

  ## Good

      defmodule PipeUnaryNPIUA do
        def bump(x), do: x |> Kernel.+(1)
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @message "piping into a unary operator is not supported"

  # The operators with a unary form, which is why only these two reach here.
  @unary_arithmetic [:+, :-]

  @impl true
  def match?(%{message: message}) when is_binary(message),
    do: String.contains?(message, @message)

  def match?(_diagnostic), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_pipe_into_unary_arithmetic,
      message:
        "Piping into a unary `+`/`-` does not do arithmetic — it applies the operator " <>
          "to the right operand alone. Use the qualified form, e.g. `x |> Kernel.+(1)`.",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         [_ | _] = nodes <- outermost(unary_rhs_nodes(ast)) do
      Sourceror.patch_string(source, Enum.map(nodes, &patch/1))
    else
      _ -> source
    end
  end

  # Deliberately NOT scoped to the diagnostic's line, unlike most Semantic
  # fixes.
  #
  # This exception carries no line at all — `Code.compile_string` RAISES here
  # rather than emitting a diagnostic, and `exception_diagnostic/1` can only
  # synthesize `position: 0` when the exception has no `:line`. Measured: `@foo`
  # outside a module comes through as position 2, this one as 0. A rule that
  # keyed on the line would find nothing and report `:no_op` forever, which is
  # exactly what the first version of this rule did.
  #
  # Scoping is not needed for safety here, which is what makes ignoring the line
  # acceptable rather than sloppy. Piping into a unary `+`/`-` NEVER compiles,
  # so there is no correct occurrence anywhere in the file to protect — every
  # one found is the defect.
  defp unary_rhs_nodes(ast) do
    {_ast, found} =
      Macro.prewalk(ast, [], fn
        {:|>, _, [_lhs, {op, _meta, [_operand]} = rhs]} = node, acc
        when op in @unary_arithmetic ->
          {node, [rhs | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  # Patching two ranges where one encloses the other corrupts the output, and
  # `x |> +(y |> +1)` is legal enough to parse. Prewalk yields outermost first,
  # so keeping only the nodes not contained in an already-kept range leaves a
  # set of disjoint patches. The enclosed ones are re-rendered by their parent's
  # patch anyway.
  defp outermost(nodes) do
    nodes
    |> Enum.map(&{&1, Sourceror.get_range(&1)})
    |> Enum.reduce([], fn {node, range}, kept ->
      if Enum.any?(kept, fn {_n, r} -> encloses?(r, range) end),
        do: kept,
        else: [{node, range} | kept]
    end)
    |> Enum.reverse()
    |> Enum.map(&elem(&1, 0))
  end

  defp encloses?(%{start: os, end: oe}, %{start: is, end: ie}),
    do: compare(os, is) != :gt and compare(oe, ie) != :lt

  defp encloses?(_outer, _inner), do: false

  defp compare(a, b) do
    {Keyword.get(a, :line), Keyword.get(a, :column)}
    |> then(fn left -> {left, {Keyword.get(b, :line), Keyword.get(b, :column)}} end)
    |> then(fn {left, right} ->
      cond do
        left < right -> :lt
        left > right -> :gt
        true -> :eq
      end
    end)
  end

  defp patch({op, _meta, [operand]} = node) do
    %{
      range: Sourceror.get_range(node),
      change: "Kernel.#{op}(#{operand |> qualify_nested() |> Sourceror.to_string()})"
    }
  end

  defp qualify_nested(operand) do
    Macro.postwalk(operand, fn
      {:|>, pipe_meta, [lhs, {op, _op_meta, [rhs]}]} when op in @unary_arithmetic ->
        qualified = {{:., [], [{:__aliases__, [alias: false], [:Kernel]}, op]}, [], [rhs]}
        {:|>, pipe_meta, [lhs, qualified]}

      node ->
        node
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
  defp line(_diagnostic), do: nil
end
