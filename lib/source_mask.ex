defmodule Credence.SourceMask do
  @moduledoc """
  Produces a *shadow* of a source file in which everything that is not code —
  string literals, charlists, sigils, heredocs, character literals and comments
  — has been blanked out, while every code byte keeps its exact position.

  Line-based syntax rules match a regex against raw source. Without a shadow
  they cannot tell code from prose, so they rewrite the inside of string
  literals. That is not hypothetical; it shipped in four rules at once:

      FixPythonModulo        IO.puts("100% done")        -> IO.puts("rem(100, done)")
      FixDivRem              IO.puts("a div b")          -> IO.puts("Kernel.div(a, b")
      FixPythonFloorDiv      IO.puts("path//to//file")   -> IO.puts("div(path, to)//file")
      FixScientificNotation  IO.puts("version 1e5")      -> IO.puts("version 1.0e5")

  Each of those outputs parses *and compiles*, so nothing downstream catches
  them — the program simply prints something the author did not write.

  ## Usage

  Match on the shadow, splice into the real line. Because the shadow is the
  same byte length as the source and every code byte is identical, a match's
  byte offsets are valid in both:

      shadow = Credence.SourceMask.mask(source)

      @pattern
      |> Regex.scan(shadow, return: :index)
      |> Enum.map(fn [{start, len} | _] -> binary_part(source, start, len) end)

  `lines/1` is the convenience form for the common per-line case.

  ## Why a hand-rolled scanner and not `:elixir_tokenizer`

  These rules only ever run on source that does **not** parse — that is what
  the syntax phase is for. The tokenizer is the first thing to give up on the
  malformed input this phase exists to repair, and a whole-file tokenize that
  fails would leave a rule with no mask at all, i.e. back to the shipped bug.

  Tokenizing line by line is not an option either: a heredoc body is not a
  valid line of Elixir, and a literal newline inside a plain `"..."` is legal,
  so string state genuinely crosses lines.

  This scanner cannot fail. On malformed input it degrades to "mask everything
  from the unterminated delimiter onward", which costs a *missed* fix rather
  than a *corrupted* string — the right direction for a phase whose reduce has
  no per-rule revert.

  ## What counts as not-code

    * `"..."` strings and `'...'` charlists, with `\\` escapes
    * `\"\"\"` and `'''` heredocs, whose terminator is only recognised when
      nothing but whitespace precedes it on the line
    * sigils `~x` / `~NAME` with every delimiter pair — `" ' / |` and the
      bracket pairs `( [ { <` — plus their heredoc forms. Elixir does not nest
      paired sigil delimiters (`~s(a (b) c)` is a syntax error), so the first
      unescaped close terminates.
    * `?x` character literals, including `?"`, `?'`, `?%`, `?#`, `?\\n`, the hex
      tail of `?\\xHH`, and multi-byte characters like `?é` — masked whole, so
      no fragment of one survives as a token. Elixir 1.20 has no `?\\xHH`
      escape and the hex tail is over-masked deliberately; the braced
      `?\\u{...}` form is **not** consumed, because unlike hex digits it could
      run past a string's opening quote (see `hex_tail_len/2`)
    * `#` comments to end of line, anywhere on the line

  Interpolation is the deliberate exception: the contents of `\#{...}` are real
  code and are left visible, with brace depth tracked so `\#{%{a: 1}}` finds its
  own closing brace. Uppercase sigils do not interpolate, so `~S(\#{x})` stays
  masked.
  """

  # Byte written over every non-code byte. Chosen so a pattern built from
  # `\w`, `\s`, `\d` or literal punctuation cannot match it — those are what
  # rules key on, so masking neither creates such a match nor alters one that
  # spans only code bytes.
  #
  # It is NOT inert to every class, and a rule author has to know which:
  # `\S`, `.` and any negated class (`[^\n]`) DO match it, because it is a
  # non-newline non-whitespace byte and nothing can change that. The
  # consequence is that a greedy `\S+` or `.+?` will *span* a literal in the
  # shadow rather than stop at it. That is usually right — in
  # `IO.puts("a") div 2` the left operand genuinely is `IO.puts("a")`, and
  # splicing it out of the real line reproduces it exactly, which is how
  # `fix_div_rem.ex` works. It is wrong for a pattern that relies on a
  # literal's *delimiter* as a boundary, since the delimiter is blanked too.
  # Such a rule wants `self_contained?/2` and the raw line, not the shadow.
  @blank 0x01

  # Stand-in `prev` values for "the previous thing was not a single ASCII byte".
  # `prev` exists only to answer `word_byte?/1`, so a multi-byte character can
  # report what it MEANS instead of handing over a continuation byte that means
  # nothing on its own. `@ident` is an ordinary word byte; `@blank` is not.
  @ident ?_

  # "Could this byte be the tail of an identifier?" — asked only of the byte
  # BEFORE a `?`, to tell `even?` from the character literal `?x`.
  #
  # Deliberately still ASCII-only. `prev` is not always a source byte: a
  # multi-byte character is decoded in `code_scan_byte/5` and reports itself
  # here as `@ident` or `@blank`, so this guard never has to reason about a
  # continuation byte it cannot interpret on its own.
  defguardp word_byte?(c)
            when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_

  @doc """
  Returns a binary of exactly the same byte length as `source`, with every
  newline preserved in place and every non-code byte replaced by `0x01`.
  """
  @spec mask(String.t()) :: String.t()
  def mask(source) do
    source
    |> scan([:code], 0, true, [])
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  @doc """
  The parser's 1-indexed `{line, column}` as a 0-indexed **byte** offset into
  `source`. `:error` when the position is not inside `source`.

  ## Bytes, and why that is not a detail

  The parser counts columns in **graphemes** — a combining accent, a ZWJ emoji and a
  flag are each one column. So the conversion has to cross from grapheme space to
  byte space, which is the `byte_size(String.slice(...))` below.

  It has to land in *byte* space because that is the only space `mask/1` shares with
  its input. The shadow is byte-for-byte the same length, and deliberately so — but
  it is **not** the same number of graphemes, because a multi-byte character is
  replaced by one blank byte per byte. Measured on `x = "héllo"`: 41 bytes of source
  and 41 of shadow, 40 graphemes of source and 41 of shadow; on a comment holding one
  flag emoji, 44 bytes each but 37 graphemes against 44.

  A scan that computes grapheme offsets from the source and then indexes the shadow
  therefore drifts by one position per extra byte, and any rule doing it goes inert
  on the first file containing a non-ASCII comment. `Credence.Syntax.WhenGuardPosition`
  did exactly that and was silently declining every such file before this existed.
  """
  @spec byte_offset(String.t(), pos_integer(), pos_integer()) ::
          {:ok, non_neg_integer()} | :error
  def byte_offset(source, line, column) do
    lines = String.split(source, "\n")

    with true <- line >= 1 and line <= length(lines),
         target = Enum.at(lines, line - 1),
         true <- column >= 1 and column - 1 <= String.length(target) do
      preceding =
        lines
        |> Enum.take(line - 1)
        |> Enum.reduce(0, fn l, acc -> acc + byte_size(l) + 1 end)

      {:ok, preceding + byte_size(String.slice(target, 0, column - 1))}
    else
      _ -> :error
    end
  end

  @doc """
  True for a single byte of `mask/1`'s output that stands in for non-code.

  For a rule that scans the shadow **character by character** rather than with a
  regex. `0x01` is not whitespace and not a word byte, so a hand-written scan that
  only knows about `" "`, `"\\t"` and `"\\n"` stops dead at the first blanked comment
  or string and silently declines. Ask this instead of comparing to `0x01`, which
  would put a second copy of that constant outside this module.

  Skipping blanks cannot reach *into* a literal: `mask/1` blanks a string's quotes
  along with its contents, so a scan that steps over blanks steps over the whole
  literal and lands on the code byte before it.

  Takes either the one-byte binary a `String.slice/3` yields or the integer an
  `:binary.at/2` yields, because a byte-wise scan wants the latter — see
  `byte_offset/3` for why such a scan must be byte-wise in the first place.
  """
  @spec blank?(String.t() | byte()) :: boolean()
  def blank?(@blank), do: true
  def blank?(<<@blank>>), do: true
  def blank?(_byte), do: false

  @doc """
  The nearest bracket **opener** enclosing `pos`, as `{:ok, index, byte}`, or `:none`.

  Walks backwards from `pos`, skipping any bracket pair that closes before it, so
  `%{a: f(1, 2), …}` reports the `{` and not the `(`. `byte` is the opener itself —
  `?(`, `?[` or `?{` — which is what tells a caller whether it is inside a map, a list
  or a call without a second scan.

  Give it a **shadow**, not raw source. A bracket inside a string or a comment is
  indistinguishable from a real one otherwise, and the only reason the index it
  returns is usable against the raw source is `mask/1`'s byte-length invariant. Note
  that `Credence.Syntax.FixKeywordBeforePositionalArgument.find_open_paren/3` is the
  raw-source predecessor of this function; its own moduledoc records that it "runs
  straight through a string literal" and compensates with a blunt decline list. It
  should adopt this, which would let that list shrink — but that is a widen of a
  shipped rule and needs its own verification, so it has not been done here.
  """
  @spec enclosing_opener(String.t(), non_neg_integer()) ::
          {:ok, non_neg_integer(), byte()} | :none
  def enclosing_opener(shadow, pos) do
    (pos - 1)..0//-1
    |> Enum.reduce_while(0, fn index, depth ->
      byte = :binary.at(shadow, index)

      cond do
        byte in [?), ?], ?}] -> {:cont, depth + 1}
        byte in [?(, ?[, ?{] and depth == 0 -> {:halt, {:ok, index, byte}}
        byte in [?(, ?[, ?{] -> {:cont, depth - 1}
        true -> {:cont, depth}
      end
    end)
    |> case do
      {:ok, index, byte} -> {:ok, index, byte}
      _depth -> :none
    end
  end

  @doc """
  Pairs every source line with its shadow, as `{line, shadow}`.

  `mask/1` preserves newlines byte-for-byte, so both splits always produce the
  same number of elements and `Enum.zip/2` cannot truncate.
  """
  @spec lines(String.t()) :: [{String.t(), String.t()}]
  def lines(source) do
    Enum.zip(String.split(source, "\n"), String.split(mask(source), "\n"))
  end

  @doc """
  True when this line lies outside every multi-line literal — that is, when
  masking it *on its own* would have produced the shadow the whole file gave it.

  Both arguments come from one `lines/1` pair.

  ## Why a rule would want this rather than the shadow

  Matching the shadow is the right move when the pattern keys on code bytes. It
  is the *wrong* move when the pattern keys on the delimiters themselves, because
  masking blanks a string literal's quotes along with its contents — so a rule
  looking for `@doc "..."` finds nothing in the shadow, and one looking for a
  `~r/.../` sigil finds nothing either. Those rules must match the raw line, and
  what they actually need to know is the narrower question this answers: *is this
  line inside a heredoc or a multi-line string?*

  It is also the escape hatch for a rule whose rewrite re-masks as it goes.
  Re-masking a line after rewriting it is only sound where the line stands alone,
  since heredoc and multi-line-string state crosses lines.

  Either way the failure direction is a missed fix on a line inside a multi-line
  literal, never a corrupted one — the same trade `mask/1` makes on malformed
  input.
  """
  @spec self_contained?(String.t(), String.t()) :: boolean()
  def self_contained?(line, shadow), do: mask(line) == shadow

  @doc """
  Replace `pattern` with `replacement` in the **code bytes** of `line`, leaving
  any match that falls inside a string, a charlist, a sigil or a comment alone.

  `line` and `shadow` are one pair from `lines/1`. `pattern` is a binary or a
  `Regex`; `replacement` is a plain binary (no backreferences — this exists for
  the several rules whose replacement is a fixed call name).

  `opts`: `global: false` replaces only the first code match (default `true`).

  ## Why this is a separate function and not `String.replace/4`

  Because `mask/1` returns a binary of exactly the same byte length with
  newlines in place, a match found in the shadow has the *same offsets* in the
  real line. So the search runs on the shadow, where non-code bytes cannot
  match, and the splice runs on the line, where the original bytes are intact.
  Doing it the obvious way instead — search and replace the raw line — is the
  byte-scope defect this module exists to prevent, and it has been found live
  five times (T3.7, T3.10, and `Semantic.UndefinedFunction`, whose per-line
  replacements rewrote a same-named call inside a string literal and inside a
  trailing comment).

  The failure direction is a missed replacement, never a corrupted one.
  """
  @spec replace_code(String.t(), String.t(), String.t() | Regex.t(), String.t(), keyword()) ::
          String.t()
  def replace_code(line, shadow, pattern, replacement, opts \\ []) do
    global? = Keyword.get(opts, :global, true)

    shadow
    |> code_matches(pattern, global?)
    |> Enum.reverse()
    |> Enum.reduce(line, fn {start, len}, acc ->
      <<head::binary-size(^start), _::binary-size(^len), tail::binary>> = acc
      head <> replacement <> tail
    end)
  end

  defp code_matches(shadow, %Regex{} = re, global?) do
    Regex.scan(re, shadow, return: :index, capture: :first)
    |> Enum.map(&hd/1)
    |> take_matches(global?)
  end

  defp code_matches(shadow, pattern, global?) when is_binary(pattern) do
    shadow
    |> all_binary_matches(pattern, 0, [])
    |> Enum.reverse()
    |> take_matches(global?)
  end

  defp all_binary_matches(_shadow, "", _from, acc), do: acc

  defp all_binary_matches(shadow, pattern, from, acc) do
    case :binary.match(shadow, pattern, scope: {from, byte_size(shadow) - from}) do
      :nomatch -> acc
      {start, len} -> all_binary_matches(shadow, pattern, start + len, [{start, len} | acc])
    end
  end

  defp take_matches(matches, true), do: matches
  defp take_matches(matches, false), do: Enum.take(matches, 1)

  defp scan(<<>>, _stack, _prev, _bol, acc), do: acc

  defp scan(bin, [{:str, _, _, _} | _] = stack, prev, bol, acc),
    do: str_scan(bin, stack, prev, bol, acc)

  defp scan(bin, stack, prev, bol, acc), do: code_scan(bin, stack, prev, bol, acc)

  # ── inside a string / charlist / sigil / heredoc ──────────────────────

  # backslash-newline: keep the newline so line offsets stay aligned
  defp str_scan(<<"\\\n", rest::binary>>, stack, _prev, _bol, acc),
    do: scan(rest, stack, ?\n, true, [?\n, @blank | acc])

  # any other escape consumes two bytes (this is also how the tokenizer
  # decides whether a terminator is escaped, including in uppercase sigils)
  defp str_scan(<<"\\", c, rest::binary>>, stack, _prev, _bol, acc),
    do: scan(rest, stack, c, false, [@blank, @blank | acc])

  defp str_scan(<<"\n", rest::binary>>, stack, _prev, _bol, acc),
    do: scan(rest, stack, ?\n, true, [?\n | acc])

  # `#{` opens real code, but only in an interpolating literal
  defp str_scan(<<"\#{", rest::binary>>, [{:str, _, true, _} | _] = stack, _prev, _bol, acc),
    do: scan(rest, [{:interp, 0} | stack], ?{, false, [@blank, @blank | acc])

  defp str_scan(bin, [{:str, close, _interp?, heredoc?} | outer] = stack, _prev, bol, acc) do
    if terminates?(bin, close, heredoc?, bol) do
      n = byte_size(close)
      <<_::binary-size(^n), rest::binary>> = bin
      scan(rest, outer, :binary.last(close), false, blanks(n, acc))
    else
      <<c, rest::binary>> = bin
      scan(rest, stack, c, bol and horizontal_space?(c), [@blank | acc])
    end
  end

  # a heredoc terminator only counts at the start of a line
  defp terminates?(bin, close, true, bol), do: bol and String.starts_with?(bin, close)
  defp terminates?(bin, close, false, _bol), do: String.starts_with?(bin, close)

  # ── code (top level, or inside #{...}) ────────────────────────────────

  defp code_scan(<<"\n", rest::binary>>, stack, _prev, _bol, acc),
    do: scan(rest, stack, ?\n, true, [?\n | acc])

  defp code_scan(<<"#", rest::binary>>, stack, _prev, _bol, acc) do
    n = comment_len(rest, 0)
    <<_::binary-size(^n), rest_after::binary>> = rest
    scan(rest_after, stack, ?#, false, blanks(n + 1, acc))
  end

  # ?\n ?\\ ?\s — a `?` is a character literal unless it is the tail of an
  # identifier (`even?`), which is exactly "the previous byte is a word byte".
  #
  # A hex tail is still consumed; a BRACED one is not. See `hex_tail_len/2` for
  # why the two are treated differently — the short version is that hex digits
  # cannot cross a delimiter and `?\u{...}` could, which let `FixPythonModulo`
  # rewrite the inside of a string literal.
  #
  # Both clauses hand `@blank` forward as `prev`, not the literal's own byte.
  # `prev` answers "what did the byte before this one look like *in the shadow*",
  # and a masked literal's last shadow byte is a blank. Passing the source byte
  # made a literal's own character decide the NEXT `?`: in `?a?"x" + 1` the
  # trailing `a` read as an identifier tail, so `?"` was left unmasked, the real
  # string was mistaken for a terminated one, and ` + 1` — which is inside the
  # string — stood in the shadow as code. That is the under-masking direction,
  # the one that corrupts source rather than costing a fix.
  defp code_scan(<<"?\\", c, rest::binary>>, stack, prev, _bol, acc)
       when not word_byte?(prev) and c != ?\n do
    # Mutually exclusive: `hex_tail_len/2` fires only for `x`/`u`, which are
    # ASCII, and `utf8_tail_len/2` only for a UTF-8 lead byte.
    n = hex_tail_len(c, rest) + utf8_tail_len(c, rest)
    <<_::binary-size(^n), rest_after::binary>> = rest
    scan(rest_after, stack, @blank, false, blanks(3 + n, acc))
  end

  # ?a ?" ?' ?% ?# — masking these keeps `?"` from opening a phantom string
  defp code_scan(<<"?", c, rest::binary>>, stack, prev, _bol, acc)
       when not word_byte?(prev) and c != ?\n do
    n = utf8_tail_len(c, rest)
    <<_::binary-size(^n), rest_after::binary>> = rest
    scan(rest_after, stack, @blank, false, blanks(2 + n, acc))
  end

  defp code_scan(<<"~", rest::binary>>, stack, prev, bol, acc) do
    case sigil_open(rest) do
      {:ok, len, close, interp?, heredoc?} ->
        <<_::binary-size(^len), after_delim::binary>> = rest

        scan(
          after_delim,
          [{:str, close, interp?, heredoc?} | stack],
          :binary.last(close),
          false,
          blanks(len + 1, acc)
        )

      :error ->
        # ~~~ (bitwise not), ~> and friends are plain operators
        code_scan_byte(<<"~", rest::binary>>, stack, prev, bol, acc)
    end
  end

  defp code_scan(<<"\"\"\"", rest::binary>>, stack, _prev, _bol, acc),
    do: scan(rest, [{:str, "\"\"\"", true, true} | stack], ?", false, blanks(3, acc))

  defp code_scan(<<"'''", rest::binary>>, stack, _prev, _bol, acc),
    do: scan(rest, [{:str, "'''", true, true} | stack], ?', false, blanks(3, acc))

  defp code_scan(<<"\"", rest::binary>>, stack, _prev, _bol, acc),
    do: scan(rest, [{:str, "\"", true, false} | stack], ?", false, [@blank | acc])

  defp code_scan(<<"'", rest::binary>>, stack, _prev, _bol, acc),
    do: scan(rest, [{:str, "'", true, false} | stack], ?', false, [@blank | acc])

  # brace tracking so `#{%{a: 1}}` finds the right closing brace
  defp code_scan(<<"{", rest::binary>>, [{:interp, d} | outer], _prev, _bol, acc),
    do: scan(rest, [{:interp, d + 1} | outer], ?{, false, [?{ | acc])

  defp code_scan(<<"}", rest::binary>>, [{:interp, 0} | outer], _prev, _bol, acc),
    do: scan(rest, outer, ?}, false, [@blank | acc])

  defp code_scan(<<"}", rest::binary>>, [{:interp, d} | outer], _prev, _bol, acc),
    do: scan(rest, [{:interp, d - 1} | outer], ?}, false, [?} | acc])

  defp code_scan(bin, stack, prev, bol, acc), do: code_scan_byte(bin, stack, prev, bol, acc)

  # A whole multi-byte character, decoded so `prev` can say what it was.
  #
  # This is the only place that can tell `café?"x"` from `—?"x"`. Both put a byte
  # >= 0x80 immediately before a `?`, but only the first is an identifier tail,
  # and the two want opposite answers: `?"` is an identifier suffix after `café`
  # and a character literal after an em dash. Judging that from `prev` alone is
  # impossible — a continuation byte like 0xA9 belongs to any number of
  # characters — so the character is decoded here and reports itself.
  #
  # Elixir takes identifiers from UAX-31, so letters, marks and digits continue
  # an identifier and everything else does not. Non-ASCII punctuation never
  # parses in code position, but this scanner runs on source that does NOT parse,
  # which is exactly why the em-dash case has to be handled rather than assumed
  # away. Invalid UTF-8 falls through to the byte clause below and is treated as
  # a non-word byte — the over-masking direction.
  defp code_scan_byte(<<c::utf8, rest::binary>>, stack, _prev, _bol, acc) when c >= 0x80 do
    prev = if identifier_char?(c), do: @ident, else: @blank
    scan(rest, stack, prev, false, [<<c::utf8>> | acc])
  end

  defp code_scan_byte(<<c, rest::binary>>, stack, _prev, bol, acc),
    do: scan(rest, stack, c, bol and horizontal_space?(c), [c | acc])

  defp identifier_char?(c), do: String.match?(<<c::utf8>>, ~r/[[:alpha:][:digit:]\p{M}]/u)

  # ── small helpers ─────────────────────────────────────────────────────

  # Length of the numeric tail of a `?\` escape, so it can be masked with the
  # rest of the literal. Over-consuming on malformed input is safe: it blanks
  # more, which can only cost a missed fix.
  # A character literal is one CHARACTER, and a character is up to four bytes.
  # Masking `?` plus a single byte left the rest of a multi-byte one standing:
  # `?é` produced a shadow ending in a bare 0xA9 and `?"` (U+201C) one ending in
  # 0x80 0x9C — neither is valid UTF-8, and an invalid subject is something
  # `Regex.scan/3` can reject outright, which would cost every rule on that file
  # rather than one match.
  #
  # Only bytes that really are continuations are counted, so malformed UTF-8
  # consumes LESS rather than eating the code byte that follows it — the same
  # "a missed fix beats a corrupted source" bias the rest of the scanner takes.
  # Elixir 1.20 has no `?\xHH` escape — its tokenizer reads `?\x41` as the
  # character `x` followed by the INTEGER 41 — so blanking the digits hides real
  # code. It is kept anyway, deliberately: hex digits cannot cross a delimiter,
  # so the cost is bounded at a missed fix, and the alternative is worse. Leaving
  # `41` visible in `?\x41 % 2` invites a rule to "repair" a modulo that is only
  # there because the file already does not parse, which is how
  # `FixPythonModulo` turned it into `?\xrem(41, 2)`.
  #
  # The braced form `?\u{...}` is NOT kept, and that asymmetry is the whole
  # point. It ran to `}` or end of line, so it could swallow a string's OPENING
  # quote — `?\u{"a}b % 2" <> y` released the scanner into code state INSIDE the
  # string and `FixPythonModulo` rewrote its contents. Bounded over-masking is
  # the documented bias; crossing a delimiter is the failure this module exists
  # to prevent.
  defp hex_tail_len(c, rest) when c in [?x, ?u], do: hex_len(rest, 0)
  defp hex_tail_len(_c, _rest), do: 0

  defp hex_len(<<c, rest::binary>>, n) when c in ?0..?9 or c in ?a..?f or c in ?A..?F,
    do: hex_len(rest, n + 1)

  defp hex_len(_bin, n), do: n

  defp utf8_tail_len(c, rest), do: continuations(rest, expected_continuations(c), 0)

  defp expected_continuations(c) when c in 0xC2..0xDF, do: 1
  defp expected_continuations(c) when c in 0xE0..0xEF, do: 2
  defp expected_continuations(c) when c in 0xF0..0xF4, do: 3
  defp expected_continuations(_c), do: 0

  defp continuations(_bin, 0, n), do: n

  defp continuations(<<c, rest::binary>>, want, n) when c in 0x80..0xBF,
    do: continuations(rest, want - 1, n + 1)

  defp continuations(_bin, _want, n), do: n

  # A sigil is `~`, a name, then a delimiter. Single-letter names may be lower
  # or upper case; multi-letter names must start with an upper case letter.
  # Lower case means interpolation and escapes are active.
  defp sigil_open(bin) do
    {name, rest} = take_name(bin, 0)

    cond do
      name == 0 -> :error
      name > 1 and not upper?(:binary.first(bin)) -> :error
      true -> sigil_delimiter(rest, name, lower?(:binary.first(bin)))
    end
  end

  defp sigil_delimiter(<<"\"\"\"", _::binary>>, name, interp?),
    do: {:ok, name + 3, "\"\"\"", interp?, true}

  defp sigil_delimiter(<<"'''", _::binary>>, name, interp?),
    do: {:ok, name + 3, "'''", interp?, true}

  defp sigil_delimiter(<<c, _::binary>>, name, interp?) when c in [?", ?', ?/, ?|],
    do: {:ok, name + 1, <<c>>, interp?, false}

  defp sigil_delimiter(<<?(, _::binary>>, name, interp?), do: {:ok, name + 1, ")", interp?, false}
  defp sigil_delimiter(<<?[, _::binary>>, name, interp?), do: {:ok, name + 1, "]", interp?, false}
  defp sigil_delimiter(<<?{, _::binary>>, name, interp?), do: {:ok, name + 1, "}", interp?, false}
  defp sigil_delimiter(<<?<, _::binary>>, name, interp?), do: {:ok, name + 1, ">", interp?, false}
  defp sigil_delimiter(_, _name, _interp?), do: :error

  # A sigil name is one lowercase letter, or an uppercase letter followed by
  # alphanumerics — `~B64(...)` and `~ABC123(...)` are both real sigils. Counting
  # only letters stopped at the first digit, so `sigil_delimiter/3` was handed `6`
  # instead of `(`, the sigil went unrecognised, and its body was never masked.
  # `~B64(100% done)` came out of the shadow whole, which is `FixPythonModulo`'s
  # shipped bug verbatim — the first entry in this module's own moduledoc.
  #
  # Only the first character may be a letter-only; the `name > 1` check in
  # `sigil_open/1` is what still rejects a lowercase multi-character name.
  defp take_name(<<c, rest::binary>>, 0) when c in ?a..?z or c in ?A..?Z,
    do: take_name(rest, 1)

  defp take_name(<<c, rest::binary>>, n)
       when n > 0 and (c in ?a..?z or c in ?A..?Z or c in ?0..?9),
       do: take_name(rest, n + 1)

  defp take_name(bin, n), do: {n, bin}

  defp lower?(c), do: c in ?a..?z
  defp upper?(c), do: c in ?A..?Z

  defp comment_len(<<"\n", _::binary>>, n), do: n
  defp comment_len(<<>>, n), do: n
  defp comment_len(<<_, rest::binary>>, n), do: comment_len(rest, n + 1)

  defp horizontal_space?(c), do: c == ?\s or c == ?\t

  defp blanks(0, acc), do: acc
  defp blanks(n, acc), do: blanks(n - 1, [@blank | acc])
end
