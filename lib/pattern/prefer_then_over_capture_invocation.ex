defmodule Credence.Pattern.PreferThenOverCaptureInvocation do
  @moduledoc """
  Detects immediately-invoked captures `(&body).()` in pipelines and
  rewrites them to use `Kernel.then/2` (Elixir 1.12+), which is the
  idiomatic replacement.

  LLMs often produce `|> (&(&1 == String.reverse(&1))).()` — a capture
  expression applied with `.()` at the end of a pipe. This is
  non-idiomatic; `Kernel.then/2` was added in Elixir 1.12 specifically
  for this purpose.

  Only captures that use exactly `&1` (arity 1) are rewritten. Captures
  that use `&2` or higher (arity > 1) or that don't use `&1` at all
  (arity 0) are left alone because `then/2` expects an arity-1 function
  and would raise a different error than the original `.()` call.

  ## Bad

      number
      |> Integer.to_string()
      |> (&(&1 == String.reverse(&1))).()

  ## Good

      number
      |> Integer.to_string()
      |> then(&(&1 == String.reverse(&1)))
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:|>, meta, [_left, {{:., _, [{:&, _, [body]}]}, _, []}]} = node, issues ->
          if arity_one_capture?(body) do
            issue = %Issue{
              rule: :prefer_then_over_capture_invocation,
              message:
                "Avoid applying captures with `.()` in a pipeline. " <>
                  "Use `then/2` instead: `|> then(&body)`.",
              meta: %{line: Keyword.get(meta, :line)}
            }

            {node, [issue | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    # `... |> (&body).()` → `... |> Kernel.then(&body)`.
    #
    # We patch the `.()`-application node on the pipe's right in
    # place. Sourceror's range for the application starts at the `&`,
    # excluding the wrapping parentheses, whose metadata supplies the
    # true start even when whitespace separates `(` and `&`.
    {_ast, patches} =
      Macro.prewalk(ast, [], fn
        {:|>, _, [_left, {{:., _, [{:&, _, [body]} = capture_node]}, _, []} = dotcall]} = node,
        acc ->
          if arity_one_capture?(body) do
            case Sourceror.get_range(dotcall) do
              nil ->
                {node, acc}

              %Sourceror.Range{start: start, end: stop} ->
                start_at_paren = capture_paren_start(capture_node, start)
                range = %Sourceror.Range{start: start_at_paren, end: stop}

                change =
                  Credence.RuleHelpers.render_replacement(
                    {{:., [], [{:__aliases__, [], [:Kernel]}, :then]}, [], [capture_node]},
                    range
                  )

                {node, [%{range: range, change: change} | acc]}
            end
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(patches)
  end

  defp capture_paren_start({:&, meta, _}, fallback) do
    case Keyword.get(meta, :parens) do
      parens when is_list(parens) -> Keyword.take(parens, [:line, :column])
      _ -> Keyword.update!(fallback, :column, &(&1 - 1))
    end
  end

  # Returns true if the capture body uses &1 (positional placeholder for the
  # first argument) and does NOT use &2 or higher. This ensures the capture is
  # exactly arity 1 — the only safe case for rewriting to then/2, which expects
  # an arity-1 function.
  defp arity_one_capture?(body) do
    {_found, {has_one, has_higher}} =
      Macro.prewalk(body, {false, false}, fn
        {:&, _, [n]}, {_has_one, has_higher} when is_integer(n) and n >= 1 ->
          {nil, {true, has_higher or n > 1}}

        node, acc ->
          {node, acc}
      end)

    has_one and not has_higher
  end
end
