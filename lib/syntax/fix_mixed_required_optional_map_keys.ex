defmodule Credence.Syntax.FixMixedRequiredOptionalMapKeys do
  @moduledoc """
  Rewrites a keyword-shorthand map entry that sits before an arrow entry into arrow
  form, so the map parses.

      %{state: atom(), optional(atom()) => any()}   ->  %{:state => atom(), …}
      %{state: :init, optional(k) => v}             ->  %{:state => :init, …}

  Elixir requires keyword entries to come **last** in lists and maps, so this is a hard
  parse error and the whole file is dark: no compiler warning, no Semantic diagnostic,
  no Pattern check, nothing downstream sees the module at all.

      unexpected expression after keyword list. Keyword lists must always come last
      in lists and maps. … Syntax error after: ','

  The name is the one docs/23 tracks, from the `@type` shape where the mixture is a
  `required` shorthand beside an `optional(…) =>` entry. The rule is not limited to
  types — a map literal produces the byte-identical error and takes the same repair.

  ## Arrow-ify rather than move-last, and why it is not a coin flip

  The disposition offers both "arrow-ify the keyword entry" and "move it last". They
  are the same map — `%{a: 1, "k" => 2}` repaired either way evaluates to
  `%{:a => 1, "k" => 2}` — so the choice is about the edit, not the meaning. Arrow-ify
  wins on three counts: it is local (no text moves across the container, so comments
  and line structure survive), it preserves the author's ordering, and it needs no
  knowledge of where the container **ends**, which move-last does.

  ## One entry per pass, and the parser finds each one

  The reported column is the comma immediately **after** the offending keyword entry,
  which makes the loop fall out for free — repair that one entry, ask again. Measured
  on `%{a: 1, b: 2, "k" => 3}`:

      column 17 (the comma after `b: 2`)  ->  %{a: 1, :b => 2, "k" => 3}
      column 11 (the comma after `a: 1`)  ->  %{:a => 1, :b => 2, "k" => 3}
      parses

  All of it in one `fix/1` call, and that is required rather than tidy: the Syntax
  round is a single `Enum.reduce` (`lib/syntax.ex:93`) calling each `fix/1` once, and
  `commit_or_roll_back/4` discards the round if the result still does not parse. A rule
  repairing one entry per call would repair nothing at all on a map with two.

  ## Scope, every boundary executed

  The container must be a plain map — `{` with `%` immediately before it. Requiring the
  `%` is also what excludes structs, since `%Foo{` has `o` there.

      %{a: 1, "k" => 2}      arrow-ified, parses     — covered
      [a: 1, 2]              syntax error before `'=>'`  — declined
      {a: 1, 2}              syntax error before `'=>'`  — declined
      f(a: 1, 2)             `FixKeywordBeforePositionalArgument`'s job — declined
      %Foo{a: 1, "k" => 2}   parses, but a struct cannot take a `=>` key at all,
                             so the module stays broken and the defect is a
                             different one                             — declined

  A list and a tuple are the interesting exclusions: they raise the same parse error,
  and arrow-ifying them is *invalid* — `[:a => 1, 2]` is `syntax error before: '=>'`.
  Their repair is move-last, which is a different rule with a different safety
  argument, so this one declines rather than half-covering them.

  Key shapes are not restricted, because every one of them arrow-ifies:

      %{"a b": 1, "k" => 2}   ->  %{:"a b" => 1, …}   parses, same map
      %{valid?: 1, "k" => 2}  ->  %{:valid? => 1, …}  parses
      %{a: :b, "k" => 2}      ->  %{:a => :b, …}      the value's colon is untouched

  ## Bad (won't parse)

      @type t :: %{state: atom(), optional(atom()) => any()}

  ## Good

      @type t :: %{:state => atom(), optional(atom()) => any()}
  """
  use Credence.Syntax.Rule

  alias Credence.Issue
  alias Credence.SourceMask

  # The parser's own words. Matching the message rather than only the `','` token is
  # what separates this from every other error that stops at a comma.
  @message_fragment "unexpected expression after keyword list"

  @impl true
  def analyze(source) do
    {_repaired, lines} = repairs(source)

    Enum.map(lines, fn line ->
      %Issue{
        rule: :fix_mixed_required_optional_map_keys,
        message:
          "a keyword entry (`key: value`) before an arrow entry (`k => v`) in a map is " <>
            "not valid Elixir — keyword entries must come last — so the file does not " <>
            "parse and nothing in it compiles. Write the key in arrow form.",
        meta: %{line: line}
      }
    end)
  end

  @impl true
  def fix(source) do
    {repaired, _lines} = repairs(source)
    repaired
  end

  # The one loop both callbacks share, so they cannot disagree about how many entries
  # need rewriting. Terminates because each pass replaces `key:` with `:key =>` and so
  # strictly reduces the number of keyword entries the parser can still object to.
  defp repairs(source), do: repairs(source, [])

  defp repairs(source, acc) do
    case locate(source) do
      {:ok, key_start, colon_at} ->
        repairs(arrow_ify(source, key_start, colon_at), [
          line_of(source, colon_at) | acc
        ])

      :none ->
        {source, Enum.reverse(acc)}
    end
  end

  # Ask the parser where the file stops, then require the position to really be this
  # defect: the right message, a comma there, a map around it, and a keyword-shaped
  # entry ending at that comma. Every offset is a byte offset — see
  # `SourceMask.byte_offset/3` for why a grapheme offset silently goes inert.
  defp locate(source) do
    with {:error, {meta, message, "','"}} <- Sourceror.parse_string(source),
         true <- to_string(message) =~ @message_fragment,
         line when is_integer(line) <- Keyword.get(meta, :line),
         column when is_integer(column) <- Keyword.get(meta, :column),
         {:ok, comma_at} <- SourceMask.byte_offset(source, line, column),
         shadow = SourceMask.mask(source),
         ?, <- byte_at(shadow, comma_at),
         {:ok, opener_at, ?{} <- SourceMask.enclosing_opener(shadow, comma_at),
         ?% <- byte_at(shadow, opener_at - 1),
         entry_start = entry_start(shadow, opener_at, comma_at),
         {:ok, colon_at} <- key_colon(shadow, entry_start, comma_at) do
      {:ok, entry_start, colon_at}
    else
      _ -> :none
    end
  end

  # The entry the parser objected to runs from the previous comma at this bracket depth
  # — or from the opener, when it is the container's first entry.
  defp entry_start(shadow, opener_at, comma_at) do
    found =
      (comma_at - 1)..(opener_at + 1)//-1
      |> Enum.reduce_while(0, fn index, depth ->
        byte = :binary.at(shadow, index)

        cond do
          byte in [?), ?], ?}] -> {:cont, depth + 1}
          byte in [?(, ?[, ?{] -> {:cont, max(depth - 1, 0)}
          byte == ?, and depth == 0 -> {:halt, index}
          true -> {:cont, depth}
        end
      end)

    if is_integer(found) and found > 0, do: found + 1, else: opener_at + 1
  end

  # The colon that terminates the key: the first one at the entry's own bracket depth,
  # with whitespace after it. Keyword syntax forbids a space *before* the colon, so
  # `key:` is unambiguous — and the first such colon is always the key's, never one
  # from the value, which is what keeps `a: :b` and `a: %{c: 1}` safe.
  defp key_colon(shadow, entry_start, comma_at) do
    entry_start..(comma_at - 1)//1
    |> Enum.reduce_while(0, fn index, depth ->
      byte = :binary.at(shadow, index)

      cond do
        byte in [?(, ?[, ?{] -> {:cont, depth + 1}
        byte in [?), ?], ?}] -> {:cont, max(depth - 1, 0)}
        byte == ?: and depth == 0 and space?(byte_at(shadow, index + 1)) -> {:halt, index}
        true -> {:cont, depth}
      end
    end)
    |> case do
      index when is_integer(index) and index >= entry_start -> {:ok, index}
      _depth -> :none
    end
  end

  # `key: value` becomes `:key => value`, in place. The entry's leading whitespace is
  # kept exactly as it was, which is what makes this safe on a multi-line map — the
  # key may be preceded by a newline and indentation.
  defp arrow_ify(source, key_start, colon_at) do
    entry_prefix = binary_part(source, key_start, colon_at - key_start)
    trivia_size = leading_trivia_size(entry_prefix, 0)
    trivia = binary_part(entry_prefix, 0, trivia_size)
    key = binary_part(entry_prefix, trivia_size, byte_size(entry_prefix) - trivia_size)

    binary_part(source, 0, key_start) <>
      trivia <>
      ":" <>
      key <>
      " =>" <>
      binary_part(source, colon_at + 1, byte_size(source) - colon_at - 1)
  end

  defp leading_trivia_size(text, index) when index < byte_size(text) do
    byte = :binary.at(text, index)

    cond do
      space?(byte) -> leading_trivia_size(text, index + 1)
      byte == ?# -> leading_trivia_size(text, comment_end(text, index + 1))
      true -> index
    end
  end

  defp leading_trivia_size(_text, index), do: index

  defp comment_end(text, index) when index < byte_size(text) do
    if :binary.at(text, index) == ?\n, do: index + 1, else: comment_end(text, index + 1)
  end

  defp comment_end(_text, index), do: index

  defp space?(byte), do: byte in [?\s, ?\t, ?\n, ?\r]

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
