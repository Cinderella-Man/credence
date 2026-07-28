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

  ## A heredoc body is not code

  The pattern is anchored to the whole line, so it can never fire inside a
  trailing comment or a mid-line string — but a *heredoc body line* is a whole
  line, and one that reads `@doc "..." do` is documentation, not a bug. This rule
  rewrote the `## Bad` example in its own moduledoc above.

  The repair is deliberately **not** to match `Credence.SourceMask`'s shadow, as
  the byte-scope rules do. Masking blanks a string literal's quotes along with
  its contents, and this pattern keys on those quotes — matching the shadow would
  match nothing at all, which is a silent retirement rather than a fix. What the
  rule needs is the narrower question `SourceMask.self_contained?/2` answers: is
  this line inside a multi-line literal? If it is, leave it alone; otherwise
  match the raw line exactly as before.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue
  alias Credence.SourceMask

  # A documentation attribute whose value is a complete double-quoted string
  # literal, immediately followed by a stray bare `do` at end of line.
  @doc_do ~r/^(\s*@(?:doc|moduledoc|typedoc)\s+"(?:[^"\\]|\\.)*")\s+do\s*$/

  @impl true
  def analyze(source) do
    source
    |> SourceMask.lines()
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {{line, shadow}, line_no} ->
      if stray_do?(line, shadow) do
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
    |> SourceMask.lines()
    |> Enum.map_join("\n", fn {line, shadow} ->
      if stray_do?(line, shadow), do: Regex.replace(@doc_do, line, "\\1"), else: line
    end)
  end

  # `analyze` and `fix` share this one predicate, so they never disagree about
  # which lines are documentation and which are the bug.
  defp stray_do?(line, shadow) do
    SourceMask.self_contained?(line, shadow) and Regex.match?(@doc_do, line)
  end
end
