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
    * `?x` character literals, including `?"`, `?'`, `?%`, `?#`, `?\\n` and the
      numeric escapes `?\\xHH`, `?\\x{...}`, `?\\uHHHH`, `?\\u{...}` — masked
      whole, so their digits cannot survive as a word token
    * `#` comments to end of line, anywhere on the line

  Interpolation is the deliberate exception: the contents of `\#{...}` are real
  code and are left visible, with brace depth tracked so `\#{%{a: 1}}` finds its
  own closing brace. Uppercase sigils do not interpolate, so `~S(\#{x})` stays
  masked.
  """

  # Byte written over every non-code byte. Chosen so it cannot take part in a
  # match: it is not a word byte, not whitespace, and not punctuation any rule
  # keys on — so masking can neither create a match nor alter one that spans
  # only code bytes.
  @blank 0x01

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
  Pairs every source line with its shadow, as `{line, shadow}`.

  `mask/1` preserves newlines byte-for-byte, so both splits always produce the
  same number of elements and `Enum.zip/2` cannot truncate.
  """
  @spec lines(String.t()) :: [{String.t(), String.t()}]
  def lines(source) do
    Enum.zip(String.split(source, "\n"), String.split(mask(source), "\n"))
  end

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

  # ?\n ?\\ ?\s ?\xHH ?\u{...} — a `?` is a character literal unless it is the
  # tail of an identifier (`even?`), which is exactly "the previous byte is a
  # word byte". The numeric escapes carry a tail that must be masked too, or
  # `?\xHH % 2` leaves `HH` in the shadow and gets rewritten mid-token.
  defp code_scan(<<"?\\", c, rest::binary>>, stack, prev, _bol, acc)
       when not word_byte?(prev) and c != ?\n do
    n = escape_tail_len(c, rest)
    <<_::binary-size(^n), rest_after::binary>> = rest
    scan(rest_after, stack, c, false, blanks(3 + n, acc))
  end

  # ?a ?" ?' ?% ?# — masking these keeps `?"` from opening a phantom string
  defp code_scan(<<"?", c, rest::binary>>, stack, prev, _bol, acc)
       when not word_byte?(prev) and c != ?\n,
       do: scan(rest, stack, c, false, blanks(2, acc))

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

  defp code_scan_byte(<<c, rest::binary>>, stack, _prev, bol, acc),
    do: scan(rest, stack, c, bol and horizontal_space?(c), [c | acc])

  # ── small helpers ─────────────────────────────────────────────────────

  # Length of the numeric tail of a `?\` escape, so it can be masked with the
  # rest of the literal. Over-consuming on malformed input is safe: it blanks
  # more, which can only cost a missed fix.
  defp escape_tail_len(c, <<"{", _::binary>> = rest) when c in [?x, ?u], do: braced_len(rest, 0)
  defp escape_tail_len(c, rest) when c in [?x, ?u], do: hex_len(rest, 0)
  defp escape_tail_len(_c, _rest), do: 0

  defp braced_len(<<"}", _::binary>>, n), do: n + 1
  defp braced_len(<<>>, n), do: n
  defp braced_len(<<"\n", _::binary>>, n), do: n
  defp braced_len(<<_, rest::binary>>, n), do: braced_len(rest, n + 1)

  defp hex_len(<<c, rest::binary>>, n) when c in ?0..?9 or c in ?a..?f or c in ?A..?F,
    do: hex_len(rest, n + 1)

  defp hex_len(_bin, n), do: n

  # A sigil is `~`, a name, then a delimiter. Single-letter names may be lower
  # or upper case; multi-letter names must start with an upper case letter.
  # Lower case means interpolation and escapes are active.
  defp sigil_open(bin) do
    {name, rest} = take_letters(bin, 0)

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

  defp take_letters(<<c, rest::binary>>, n) when c in ?a..?z or c in ?A..?Z,
    do: take_letters(rest, n + 1)

  defp take_letters(bin, n), do: {n, bin}

  defp lower?(c), do: c in ?a..?z
  defp upper?(c), do: c in ?A..?Z

  defp comment_len(<<"\n", _::binary>>, n), do: n
  defp comment_len(<<>>, n), do: n
  defp comment_len(<<_, rest::binary>>, n), do: comment_len(rest, n + 1)

  defp horizontal_space?(c), do: c == ?\s or c == ?\t

  defp blanks(0, acc), do: acc
  defp blanks(n, acc), do: blanks(n - 1, [@blank | acc])
end
