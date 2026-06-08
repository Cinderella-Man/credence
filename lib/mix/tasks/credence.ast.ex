defmodule Mix.Tasks.Credence.Ast do
  @shortdoc "Dump the Sourceror AST of a snippet (raw + layout-stripped)"

  @moduledoc """
  Print the `Sourceror.parse_string!/1` AST of a code snippet — the exact tree a
  Pattern rule's `check/2` pattern-matches against — in two views:

      mix credence.ast path/to/snippet.exs      # from a file
      echo 'Enum.map(x, & &1)' | mix credence.ast  # from stdin

    1. **Raw** — `inspect(ast, pretty: true, limit: :infinity)`, INCLUDING the
       `{:__block__, _, [literal]}` wrappers around literals, which a rule's
       `check/2` must match. This is the ground truth.
    2. **Layout-stripped** — the same tree with `:line/:column/:closing/:last/:end`
       meta dropped, for readability.

  This is an exploration-killer for rule authors (and Tunex's implementer seed):
  it hands you the tuple shape instead of making you guess it in `iex`.

  NOTE: it deliberately does **not** print the `normalize_sourceror_ast`/unwrapped
  form — that unwraps the `__block__` literal wrappers (it exists for test-time
  AST-equivalence) and would teach the wrong shape to match.
  """

  use Mix.Task

  @layout_keys [:line, :column, :closing, :last, :end, :end_of_expression, :token, :delimiter]

  @impl Mix.Task
  def run(argv) do
    code = read_source(argv)
    ast = Sourceror.parse_string!(code)

    Mix.shell().info("=== RAW (the shape check/2 matches — incl. __block__ literal wrappers) ===")
    Mix.shell().info(inspect(ast, pretty: true, limit: :infinity))

    Mix.shell().info("\n=== LAYOUT-STRIPPED (readability — :line/:column/:closing/... removed) ===")
    Mix.shell().info(inspect(strip_layout(ast), pretty: true, limit: :infinity))
  end

  # Own layout strip (a prewalk dropping layout meta) — NOT RuleHelpers'
  # private strip_layout_meta, and never `normalize_sourceror_ast` (which
  # unwraps __block__ literals — the wrong matching target).
  defp strip_layout(ast) do
    Macro.prewalk(ast, fn
      {form, meta, args} when is_list(meta) -> {form, Keyword.drop(meta, @layout_keys), args}
      other -> other
    end)
  end

  defp read_source([]), do: IO.read(:stdio, :eof) |> to_string()
  defp read_source([path | _]), do: File.read!(path)
end
