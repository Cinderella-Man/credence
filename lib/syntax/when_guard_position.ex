defmodule Credence.Syntax.WhenGuardPosition do
  @moduledoc """
  Decides which construct encloses a `syntax error before: 'when'`, so that one
  rule can apply **opposite** repairs to the two shapes that produce it.

      def positive?(x), when x > 0, do: true    delete the COMMA
      for {n, p} <- items, when p > 100 do      delete the `when `

  docs/23 tracked those as two rules to be "built together, sharing one backward
  scanner". They share this scanner, but they had to become one rule —
  `FixMisplacedWhenGuard` — because the Syntax round is a single pass and the parser
  reports only the first error, so two rules cannot repair an interleaved file. That
  moduledoc carries the measurement.

  ## Re-parsing is not a sufficient check, which is why this module exists

  The obvious safety net — apply the repair and require the result to parse — does
  **not** discriminate. Measured: for the `def`, `for`, `with`, `case` and `fn`
  shapes, deleting the comma AND deleting the `when` each yield source that parses.
  Picking the wrong one produces code that parses and means something else.

  What separates them is compilation, and that is how this mapping was derived
  rather than argued:

      construct   delete comma   delete `when`
      def/defp    compiles       undefined function def/3
      case        compiles       does not compile
      fn          compiles       does not compile
      for         undefined      compiles, and filters correctly
                  function
                  when/2
      with        does not       compiles — and SILENTLY LOSES THE GUARD
                  compile

  ## `with` declines, and that corrects docs/18

  The disposition groups `with ... <- ..., when` with the `def` shape, "delete the
  comma, not the `when`". Deleting the comma there does not compile. Deleting the
  `when` does compile — and is worse: a bare expression in a `with` clause is
  evaluated and its value discarded, so the guard stops filtering. Executed, with
  the guard's own condition false:

      with {:ok, x} <- {:ok, -5}, x > 0 do {:passed, x} else o -> {:else, o} end
      #=> {:passed, -5}

      for a <- [-5], a > 0, do: a
      #=> []

  So `for` is a real filter and `with` is not, and neither DELETION preserves the
  author's intent.

  `with` does accept a guard, though — before the `<-`, attached to the pattern, which
  is how Elixir's own stdlib writes it (`partition_supervisor.ex:446`,
  `uri.ex:493`). Executed:

      with pid when is_integer(pid) <- 5,          do: {:matched, pid}   #=> {:matched, 5}
      with pid when is_integer(pid) <- :not_an_int, do: {:matched, pid}  #=> :not_an_int

  So the repair exists and it is a **move across the `<-`**, not a deletion of either
  token. This rule only ever deletes, so `:none` is still the honest answer — but the
  reason is "out of remit", not "impossible", and docs/23 carries it as its own item.

  ## `for` has a second legal repair, and it is the weaker one

  A guard is legal in a generator PATTERN too (`Kernel.SpecialForms` doctest,
  `special_forms.ex:1431`), so `for {n, p} <- items, when p > 100` could also be
  repaired by moving the guard left of the `<-`. That looked like an intent ambiguity
  worth recording. It is not one, and both halves were executed:

    * They do not diverge. On the heterogeneous list proposed as the counterexample,
      `[{:admin, "a"}, {:guest, "b"}, :malformed]`, the filter form and the
      generator-guard form both return `["a"]` — a generator pattern already skips an
      element it does not match, so there is nothing left for the two to disagree on.

    * Deleting the `when` is strictly MORE general. A filter may be any expression; a
      guard may not. `for a <- l, String.length(inspect(a)) > 0` runs, while
      `for a when String.length(inspect(a)) > 0 <- l` is a `CompileError`, "cannot
      invoke remote function Kernel.inspect/1 inside a guard".

  So delete-the-`when` is the correct repair rather than merely the chosen one.

  ## How the scan works

  On `Credence.SourceMask.mask/1`'s shadow, never the raw source — that is what
  makes a `when` inside a string, heredoc, sigil or comment invisible here. It is
  also the primitive this repo already has for exactly this job; writing a second
  backward lexer is how the two-copies-of-one-predicate defect class starts.

  From the error position, walk backwards keeping only the bytes at bracket depth 0.
  Anything inside a bracket pair that closes before the position is skipped, which is
  what tells `for a <- f(), when p` (still `for`) from `def f(x), when p` (still
  `def`). The nearest surviving keyword wins, so a `for` inside a `def` body resolves
  to `for`.

  ## Bytes, not graphemes — the shadow is only byte-aligned

  Every offset here is a byte offset, and that is load-bearing rather than a style
  choice. `mask/1` guarantees the shadow is byte-for-byte the same LENGTH, not that it
  has the same number of graphemes: a multi-byte character becomes one blank byte per
  byte. So `x = "héllo"` is 40 graphemes of source against 41 of shadow.

  This module first computed grapheme offsets from the source and indexed the shadow
  with them. Measured consequence: on `x = "héllo"\ndef f(x), when x > 0, do: x` the
  verdict was `:none`, and with a flag emoji in a comment (7 graphemes against 1) also
  `:none` — the rule went inert on any file containing a non-ASCII comment or string,
  which is most files in most languages. It declined rather than corrupting, so no
  gate could see it. `SourceMask.byte_offset/3` is the conversion, and it is shared
  rather than local because two rules already had a private copy of it.
  """

  alias Credence.SourceMask

  # Clause-head constructs: the comma is the mistake, the guard is wanted.
  # `receive`, `try` and `cond` are absent deliberately — their repair is
  # plausible but unverified, and this module only claims what was executed.
  @clause_heads ~w(def defp defmacro defmacrop case fn)

  # Comma-separated clause lists: the `when` is the mistake.
  @filter_lists ~w(for)

  @keywords @clause_heads ++ @filter_lists ++ ~w(with receive try cond)

  @when_token "when"

  @type kind :: :clause_head | :for_filter

  @doc """
  `{:ok, kind, offset}` for the repairable shapes, `:none` otherwise.

  `offset` is a 0-based offset into `source`: for `:clause_head` it is the stray
  comma, for `:for_filter` the `w` of the `when`. Both rules delete at that offset
  and neither has to re-derive the position.
  """
  @spec locate(String.t()) :: {:ok, kind(), non_neg_integer()} | :none
  def locate(source) do
    with {:error, {meta, _msg, "'when'"}} <- Sourceror.parse_string(source),
         line when is_integer(line) <- Keyword.get(meta, :line),
         column when is_integer(column) <- Keyword.get(meta, :column),
         {:ok, when_at} <- SourceMask.byte_offset(source, line, column),
         shadow = SourceMask.mask(source),
         @when_token <- bytes(shadow, when_at, byte_size(@when_token)) do
      classify(shadow, when_at)
    else
      _ -> :none
    end
  end

  # `binary_part/3` raises past the end of the binary, and the parser can report a
  # position one past the last byte.
  defp bytes(binary, at, length) when at >= 0 and at + length <= byte_size(binary),
    do: binary_part(binary, at, length)

  defp bytes(_binary, _at, _length), do: nil

  defp classify(shadow, when_at) do
    case enclosing_keyword(shadow, when_at) do
      kw when kw in @filter_lists ->
        {:ok, :for_filter, when_at}

      kw when kw in @clause_heads ->
        case preceding_comma(shadow, when_at) do
          {:ok, comma_at} -> {:ok, :clause_head, comma_at}
          :none -> :none
        end

      _ ->
        :none
    end
  end

  # The stray comma sits before the `when`, separated only by whitespace — which
  # may include newlines: `def f(x),\n  when x > 0` puts it on the previous line,
  # so a line-local search would miss it.
  #
  # Blanked bytes are skipped too, because a comment between the clause head and its
  # guard is separator as far as this scan is concerned:
  #
  #     def f(x), # a note
  #       when x > 0, do: x
  #
  # `SourceMask.blank?/1` rather than a `0x01` literal, and it cannot step into a
  # literal — the mask blanks a string's quotes with its contents, so skipping blanks
  # crosses the whole literal and lands on the code byte before it.
  defp preceding_comma(shadow, when_at) do
    idx =
      (when_at - 1)..0//-1
      |> Enum.find(fn i -> not separator?(:binary.at(shadow, i)) end)

    case idx && :binary.at(shadow, idx) do
      ?, -> {:ok, idx}
      _ -> :none
    end
  end

  defp separator?(byte), do: byte in [?\s, ?\t, ?\n, ?\r] or SourceMask.blank?(byte)

  # Keep only the depth-0 characters before `pos`, then take the last keyword in
  # them. Reversing and folding is what makes "depth relative to `pos`" cheap: a
  # closer increments, an opener decrements, and everything in between is dropped.
  defp enclosing_keyword(shadow, pos) do
    (pos - 1)..0//-1
    |> Enum.reduce({0, []}, fn i, {depth, kept} ->
      byte = :binary.at(shadow, i)

      cond do
        byte in [?), ?], ?}] -> {depth + 1, kept}
        byte in [?(, ?[, ?{] -> {max(depth - 1, 0), kept}
        depth > 0 -> {depth, kept}
        # Walking backwards and prepending puts the kept bytes back in source order.
        # A non-ASCII byte becomes a space so the result stays valid ASCII for the
        # regex below AND keeps its word boundary — dropping it instead would splice
        # `fór` into `for`.
        byte >= 0x80 -> {depth, [?\s | kept]}
        true -> {depth, [byte | kept]}
      end
    end)
    |> elem(1)
    |> IO.iodata_to_binary()
    |> last_keyword()
  end

  defp last_keyword(text) do
    ~r/(?<![\w.:])([a-z]+)(?![\w?!])/
    |> Regex.scan(text)
    |> Enum.map(fn [_full, word] -> word end)
    |> Enum.filter(&(&1 in @keywords))
    |> List.last()
  end
end
