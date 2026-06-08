defmodule Credence.Pattern.NoAnonFnApplicationInPipe do
  @moduledoc """
  Readability rule: Detects anonymous functions applied with `.()` inside
  a pipeline.

  Applying an anonymous function directly in a pipe (e.g.
  `|> (fn x -> ... end).()`) is non-idiomatic and hard to read.
  Use `then/2` instead, which was added in Elixir 1.12 specifically
  for this purpose.

  ## Bad

      list
      |> Enum.sort()
      |> (fn s -> [1 | s] end).()

  ## Good

      list
      |> Enum.sort()
      |> then(fn s -> [1 | s] end)

      # Or with capture syntax:
      |> then(&[1 | &1])
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Match: ... |> (fn ... end).()
        {:|>, meta, [_left, {{:., _, [{:fn, _, _}]}, _, []}]} = node, issues ->
          issue = %Issue{
            rule: :no_anon_fn_application_in_pipe,
            message:
              "Avoid applying anonymous functions with `.()` inside a pipeline. " <>
                "Use `then/2` instead: `|> then(fn x -> ... end)`.",
            meta: %{line: Keyword.get(meta, :line)}
          }

          {node, [issue | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    # `... |> (fn ... end).()` → `... |> then(fn ... end)`.
    #
    # We patch the `.()`-application node (`(fn ...).()`) on the pipe's right in
    # place rather than rewriting the whole `:|>`, so chained applications each
    # get their own non-overlapping patch. Sourceror's range for the application
    # starts at the `fn` keyword, EXCLUDING the wrapping `(` that `.()` requires,
    # so we extend the range one column to the left to swallow that `(`. Without
    # this the patch strands the `(`, producing the uncompilable `|> (then(fn ...end)`.
    {_ast, patches} =
      Macro.prewalk(ast, [], fn
        {:|>, _, [_left, {{:., _, [{:fn, _, _} = fn_node]}, _, []} = dotcall]} = node, acc ->
          case Sourceror.get_range(dotcall) do
            nil ->
              {node, acc}

            %Sourceror.Range{start: start, end: stop} ->
              start_at_paren = Keyword.update!(start, :column, &(&1 - 1))
              range = %Sourceror.Range{start: start_at_paren, end: stop}
              change = Credence.RuleHelpers.render_replacement({:then, [], [fn_node]}, range)
              {node, [%{range: range, change: change} | acc]}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(patches)
  end
end
