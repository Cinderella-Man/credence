defmodule Credence.Syntax.NoDocWithDoBlock do
  @moduledoc """
  Repairs a documentation attribute written with a stray `do` block.

  LLMs repeatedly emit `@doc "..." do` — gluing a `do` onto a `@doc`
  attribute. A documentation attribute (`@doc`, `@moduledoc`, `@typedoc`)
  never takes a `do` block, and the dangling `do` has no matching `end`, so the
  module fails to parse (`missing terminator: end`). It is always a mistake, so
  this is a REPAIR: drop the trailing ` do`, which rebalances the block
  structure and leaves the attribute and its value untouched.

  The match is anchored to a documentation attribute whose value is a **complete
  double-quoted string literal** immediately followed by a bare ` do` at end of
  line. That is the canonical LLM mistake (`@doc "..." do`), and a string-literal
  doc with a do-block never compiles — so the only thing this can match is the
  bug. A normal `@doc "..."`, a `def f do`, or a value whose string merely
  contains the word "do" (which ends in a quote, not ` do`) are never touched.

  Deliberately left alone (narrowed out): a documentation attribute whose value
  is an *expression* ending in `do`, e.g. a multi-line conditional doc

      @doc (if prod? do
              "..."
            else
              "..."
            end)

  This is valid, compiling code. Because the syntax phase runs every rule's
  `fix` whenever the source fails to parse for *any* reason, a line-by-line
  regex broad enough to catch `@doc (... do` would also strip the `do` from
  this valid block when some unrelated part of the file fails to parse. Anchoring
  to a complete string literal keeps the repair to the provably-bug shape.

  ## Bad (won't parse — missing terminator: end)

      @doc "top_n_items/2" do
      def find_top_n(map, n), do: Enum.take(map, n)

  ## Good

      @doc "top_n_items/2"
      def find_top_n(map, n), do: Enum.take(map, n)
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  # A documentation attribute whose value is a complete double-quoted string
  # literal, immediately followed by a stray bare `do` at end of line.
  @doc_do ~r/^(\s*@(?:doc|moduledoc|typedoc)\s+"(?:[^"\\]|\\.)*")\s+do\s*$/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if Regex.match?(@doc_do, line) do
        [
          %Issue{
            rule: :no_doc_with_do_block,
            message: "Documentation attribute has a stray `do`; remove it.",
            meta: %{line: line_no}
          }
        ]
      else
        []
      end
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.map_join("\n", &Regex.replace(@doc_do, &1, "\\1"))
  end
end
