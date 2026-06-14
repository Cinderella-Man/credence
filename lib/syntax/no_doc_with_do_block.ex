defmodule Credence.Syntax.NoDocWithDoBlock do
  @moduledoc """
  Repairs a documentation attribute written with a stray `do` block.

  LLMs repeatedly emit `@doc "..." do` — gluing a `do` onto a `@doc`
  attribute. A documentation attribute (`@doc`, `@moduledoc`, `@typedoc`)
  never takes a `do` block, and the dangling `do` has no matching `end`, so the
  module fails to parse (`missing terminator: end`). It is always a mistake, so
  this is a REPAIR: drop the trailing ` do`, which rebalances the block
  structure and leaves the attribute and its value untouched.

  The match is anchored to a documentation attribute line that *ends* in a bare
  ` do`, so a normal `@doc "..."`, a `def f do`, or a value whose string merely
  contains the word "do" (which ends in a quote, not `do`) are never touched.

  ## Bad (won't parse — missing terminator: end)

      @doc "top_n_items/2" do
      def find_top_n(map, n), do: Enum.take(map, n)

  ## Good

      @doc "top_n_items/2"
      def find_top_n(map, n), do: Enum.take(map, n)
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  # A documentation attribute line ending in a stray bare `do`.
  @doc_do ~r/^(\s*@(?:doc|moduledoc|typedoc)\s+.+?)\s+do\s*$/

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
