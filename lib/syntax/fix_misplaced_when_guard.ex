defmodule Credence.Syntax.FixMisplacedWhenGuard do
  @moduledoc """
  Repairs a `when` written as one more comma-separated element, in either of the two
  shapes it takes — and they need opposite repairs.

      def positive?(x), when x > 0, do: true    ->  def positive?(x) when x > 0, do: true
      for {n, p} <- items, when p > 100 do      ->  for {n, p} <- items, p > 100 do

  docs/17 records these as ONE construct, "`when` overgeneralized as a
  comma-separated filter". The generator knows `when` is legal after a clause head
  and that the comprehension's generator list is comma-separated, and splices it
  into the wrong slot. Either way the tokenizer aborts and the whole file fails to
  compile, emitting the byte-identical error tuple:

      {:error, {[line: 1, column: 19], "syntax error before: ", "'when'"}}

  Also seen split across lines, with the comma left on the line above:

      def f(x),
        when x > 0,
        do: x

  ## Why this is one rule and not the two the build list named

  docs/23 tracked `fix_stray_comma_before_when_guard` and
  `fix_when_guard_in_for_comprehension` separately, "built together, sharing one
  backward scanner". They share the scanner — `Credence.Syntax.WhenGuardPosition` —
  but two rules cannot do the job, and this was measured rather than reasoned.

  The Syntax round is a single `Enum.reduce` over the rules (`lib/syntax.ex:93`):
  each `fix/1` is called once, in a fixed order. The parser only ever reports the
  FIRST error. So on a file whose `for` defect precedes its `def` defect, the
  comma rule runs first, sees `:for_filter`, declines; the `for` rule then repairs
  its own shape and stops at the clause head; the round ends still unparseable and
  `commit_or_roll_back/4` discards everything. Executed, with the two as separate
  rules:

      def THEN for  ->  parses, [{FixStrayComma…, 1}, {FixWhenGuard…, 1}]
      for THEN def  ->  parses=false, [{FixWhenGuard…, :rolled_back}]

  No rule order fixes that; reversing it just moves the failure to the other
  interleaving. One rule that can apply both repairs converges in one pass.

  ## Which repair, decided by compilation rather than by re-parsing

  Re-parsing does not discriminate: for the `def`, `for`, `with`, `case` and `fn`
  shapes, deleting the comma AND deleting the `when` each yield source that parses.
  Compiling does. `WhenGuardPosition` carries the derived mapping and the executed
  reason `with` declines — deleting its `when` compiles and silently stops the
  guard filtering, because a bare `with` clause's value is discarded.

  ## Bad (won't parse — syntax error before `'when'`)

      def positive?(x), when x > 0, do: true

  ## Good

      def positive?(x) when x > 0, do: true
  """
  use Credence.Syntax.Rule

  alias Credence.Issue
  alias Credence.Syntax.WhenGuardPosition

  # `when` itself. One adjacent space goes with it, never an adjacent newline —
  # `delete_when/2` carries which one and why.
  @when_token "when"

  @impl true
  def analyze(source) do
    {_repaired, repaired_at} = repairs(source)

    Enum.map(repaired_at, fn {kind, line} ->
      %Issue{
        rule: :fix_misplaced_when_guard,
        message: message(kind),
        meta: %{line: line}
      }
    end)
  end

  @impl true
  def fix(source) do
    {repaired, _repaired_at} = repairs(source)
    repaired
  end

  defp message(:clause_head),
    do:
      "a comma between a clause head and its `when` guard stops the parser, so " <>
        "nothing in the file compiles. Remove the comma."

  defp message(:for_filter),
    do:
      "`when` is not a comprehension filter — the filter list is comma-separated " <>
        "expressions. Remove `when`."

  # Every occurrence, both shapes, in one call — see the moduledoc for why that is
  # required rather than tidy. `{repaired_source, [{kind, line}]}`, so `analyze/1`
  # and `fix/1` cannot disagree about how many defects there are or where.
  #
  # Terminates because each edit removes at least one byte, so the source strictly
  # shortens.
  defp repairs(source), do: repairs(source, [])

  defp repairs(source, found) do
    case WhenGuardPosition.locate(source) do
      {:ok, :clause_head, comma_at} ->
        repairs(
          delete(source, comma_at, 1),
          [{:clause_head, line_of(source, comma_at)} | found]
        )

      {:ok, :for_filter, when_at} ->
        repairs(
          delete_when(source, when_at),
          [{:for_filter, line_of(source, when_at)} | found]
        )

      :none ->
        {source, Enum.reverse(found)}
    end
  end

  # Take one adjacent space along with `when`, so the filter reads as the author would
  # have written it and the repair leaves no trailing whitespace behind.
  #
  # The space after it, normally. When there is none — `for a <- l, when\n  a > 1` —
  # take the one BEFORE instead, because deleting only `when` would leave `l, ` with a
  # trailing space, and that is a new defect in exchange for the old one.
  #
  # Never the newline itself: joining the two lines is a bigger edit than the defect
  # warrants, and it would shift the line numbers of every later repair, since each is
  # located in the already-repaired source. As written no edit here removes a newline,
  # so the lines `analyze/1` reports are lines in the source the caller handed in.
  defp delete_when(source, at) do
    cond do
      byte_at(source, at + byte_size(@when_token)) == ?\s ->
        delete(source, at, byte_size(@when_token) + 1)

      byte_at(source, at - 1) == ?\s ->
        delete(source, at - 1, byte_size(@when_token) + 1)

      true ->
        delete(source, at, byte_size(@when_token))
    end
  end

  # Every offset here is a BYTE offset, because that is what `WhenGuardPosition`
  # returns and it has to be — the shadow it scans is byte-aligned with the source,
  # not grapheme-aligned. Slicing with `String.slice/3` here would reintroduce the
  # drift on the source side: one `é` earlier in the file and the edit lands a
  # position early. See `SourceMask.byte_offset/3`.
  defp delete(source, offset, length) do
    binary_part(source, 0, offset) <>
      binary_part(source, offset + length, byte_size(source) - offset - length)
  end

  defp byte_at(source, index) when index >= 0 and index < byte_size(source),
    do: :binary.at(source, index)

  defp byte_at(_source, _index), do: nil

  defp line_of(source, offset) do
    source
    |> binary_part(0, offset)
    |> :binary.matches("\n")
    |> length()
    |> Kernel.+(1)
  end
end
