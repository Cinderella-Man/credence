defmodule Credence.SourceMaskTest do
  @moduledoc """
  `Credence.SourceMask` had no test of its own until 2026-07-28, which is a poor
  place for a gap: it is the single piece of machinery every byte-scope repair in
  `lib/syntax` depends on, and a rule that trusts a wrong shadow corrupts source
  silently — the output parses, compiles, and passes the rule's own fix tests.

  These are the invariants the rules actually rely on, stated once here so each
  rule's tests do not have to re-derive them:

    * **same byte length** — a shadow offset is a line offset, which is what
      makes `binary_part/3` splicing legal;
    * **newlines in place** — so `lines/1`'s two `String.split/2` calls always
      produce the same number of elements and `Enum.zip/2` cannot truncate;
    * **code bytes identical** — a match that spans only code bytes means the
      same thing in both;
    * **every literal kind blanked**, interpolation excepted, because
      interpolation *is* code.
  """
  use ExUnit.Case, async: true

  alias Credence.SourceMask

  # 0x01 is unprintable; render it as `·` so a failure diff is readable.
  defp show(binary), do: String.replace(binary, <<1>>, "·")
  defp mask(source), do: show(SourceMask.mask(source))

  describe "mask/1 — the invariants rules splice on" do
    test "the shadow is always exactly as long as the source" do
      sources = [
        "",
        "\n",
        "x = 1",
        ~S|x = "abc"|,
        ~S|x = ~S(a)|,
        "x = 1 # note",
        "def f(x), do: x\n\nend\n"
      ]

      for source <- sources do
        assert byte_size(SourceMask.mask(source)) == byte_size(source),
               "length changed for #{inspect(source)}"
      end
    end

    test "malformed input does not raise — an unterminated literal blanks the rest" do
      # The scanner cannot fail on purpose: these rules run only on source that
      # does NOT parse, so giving up would leave a rule with no mask at all.
      for source <- [~S|"|, ~S|"""|, "~", "?", "#", ~S|'''|, ~S|x = "unterminated|] do
        assert byte_size(SourceMask.mask(source)) == byte_size(source)
      end
    end

    test "newlines stay in place, so lines/1 cannot truncate" do
      source = "a\n\"b\nc\"\nd\n"

      assert SourceMask.mask(source) |> String.split("\n") |> length() ==
               source |> String.split("\n") |> length()

      assert length(SourceMask.lines(source)) == 5
    end

    test "every code byte is unchanged" do
      source = ~S|if x == 1 and y != "z", do: f(a, b)|
      shadow = SourceMask.mask(source)

      unchanged =
        Enum.zip(:binary.bin_to_list(source), :binary.bin_to_list(shadow))
        |> Enum.filter(fn {_s, m} -> m != 1 end)
        |> Enum.all?(fn {s, m} -> s == m end)

      assert unchanged
    end
  end

  describe "mask/1 — what counts as not code" do
    test "string literals" do
      assert mask(~S|x = "abc" + 1|) == "x = ····· + 1"
    end

    test "charlists, both spellings" do
      assert mask(~S|x = 'ab' + 1|) == "x = ···· + 1"
      assert mask(~S|x = ~c"ab"|) == "x = ······"
    end

    test "sigils keep their delimiter blanked with the body" do
      assert mask(~S|x = ~S(raw) + 1|) == "x = ······· + 1"
    end

    test "comments, wherever they start" do
      assert mask("x = 1 # note") == "x = 1 ······"
      assert mask("  # whole line") == "  ············"
    end

    test "character literals, including their hex tail" do
      # `?\x41` is masked whole. Elixir 1.20 has no such escape — the tokenizer
      # reads it as the character `x` then the integer 41 — so this over-masks on
      # purpose: hex digits cannot cross a delimiter, and leaving `41` visible
      # invites a rule to "repair" a modulo that only exists because the file
      # already does not parse. The braced form is the opposite case and is NOT
      # consumed; see the leak describe block.
      assert mask(~S|x = ?a + ?\x41|) == "x = ·· + ·····"
      assert mask(~S|x = ?\n|) == "x = ···"
    end

    test "heredoc bodies, and the terminator line" do
      source = ~S'''
      @moduledoc """
      body text
      """
      '''

      assert mask(source) == "@moduledoc ···\n·········\n···\n"
    end
  end

  describe "mask/1 — UTF-8, where one byte is not one character" do
    # Both of these were real defects, found 2026-08-18 by triaging the mutation
    # sweep's survivors. They share a root cause: the scanner walks BYTES, and a
    # `?` decision was being made from the previous byte and the next byte as if
    # each were a whole character.

    test "an identifier ending in a non-ASCII letter does not open a phantom literal" do
      # `prev` is a raw byte, so before the `?` of `café?` it is 0xA9 — the tail
      # of `é`. Read as "not an identifier byte", `?"` became a character
      # literal, its two bytes were blanked, and the string's OPENING quote went
      # with them. The contents then stood in the shadow as code.
      # The `?` is a suffix on both spellings; only the identifier differs.
      assert mask(~S|x = café?("a")|) == "x = café?(···)"
      assert mask(~S|x = cafe?("a")|) == "x = cafe?(···)"

      shadow = SourceMask.mask(~S|x = café?"a div b"|)

      refute shadow =~ "div",
             "string contents visible as code — this is FixDivRem's shipped bug: #{show(shadow)}"
    end

    test "the ASCII spelling is unchanged — the fix widened the guard, it did not move it" do
      assert mask(~S|x = cafe?"a div b"|) == "x = cafe?·········"
      assert mask(~S|even?("a")|) == "even?(···)"
      assert mask(~S|x = ?"|) == "x = ··"
    end

    test "a non-ASCII byte before `?` only suppresses the literal reading, never a real one" do
      # `über` ends in ASCII `r`, so this case never depended on the guard —
      # it is the control that proves the change is not a blanket suppression.
      assert mask(~S|IO.puts über?("s")|) == "IO.puts über?(···)"
    end

    test "a character literal masks the whole character, not its first byte" do
      # `?é` is three bytes; blanking two left a bare 0xA9 standing, so the
      # shadow was not valid UTF-8 — a subject `Regex.scan/3` can reject
      # outright, which costs every rule on that file rather than one match.
      for source <- [~S|x = ?é|, ~S|x = ?“|, ~S|x = ?😀|, ~S|x = ?\é|] do
        shadow = SourceMask.mask(source)

        assert String.valid?(shadow), "shadow is not valid UTF-8 for #{inspect(source)}"
        assert shadow == "x = " <> String.duplicate(<<1>>, byte_size(source) - 4)
      end
    end

    test "byte length and UTF-8 validity hold across the Unicode cases" do
      sources = [
        ~S|x = café?"a"|,
        ~S|x = ?é|,
        ~S|x = ?😀|,
        ~S|x = "héllo" + 1|,
        ~S|x = ~S(héllo)|,
        "x = 1 # cömment",
        ~S|x = "#{übr}"|,
        ~S|:"héllo"|
      ]

      for source <- sources do
        shadow = SourceMask.mask(source)

        assert byte_size(shadow) == byte_size(source), "length changed for #{inspect(source)}"
        assert String.valid?(shadow), "invalid UTF-8 for #{inspect(source)}"
      end
    end

    test "a non-ASCII byte that is NOT an identifier tail still reads `?` as a literal" do
      # The counterpart to the `café?` case, and the reason the guard decodes the
      # character instead of accepting every byte >= 0x80. An em dash before a
      # `?` is not an identifier tail, so `?"` there really is a character
      # literal — and treating it as a suffix would leave the quote standing and
      # flip string parity for the rest of the line.
      em_dash = "x = " <> <<0x2014::utf8>> <> ~S|?"a div b"|

      assert mask(em_dash) == "x = —··a div b·"
    end

    test "a character literal does not let its own character decide the next `?`" do
      # `prev` reports what the previous byte looked like IN THE SHADOW, and a
      # masked literal's last shadow byte is a blank. Handing the literal's own
      # character forward instead made `?a` mark the following `?` as an
      # identifier tail: `?"` stayed unmasked, the real string was read as
      # terminated, and ` + 1` — string content — stood in the shadow as code.
      assert mask(~S|x = ?a?"x" + 1|) == "x = ····x·····"
      assert mask(~S|x = ?é?"SECRET"|) == "x = ·····SECRET·"
    end

    test "malformed UTF-8 consumes less rather than eating the byte after it" do
      # Only bytes actually in 0x80..0xBF are taken as continuations, so a lead
      # byte with no continuation cannot swallow the code that follows it. The
      # module's stated bias: a missed fix beats a corrupted source.
      truncated = <<"x = ?", 0xC3, "+ 1">>

      shadow = SourceMask.mask(truncated)

      assert byte_size(shadow) == byte_size(truncated)
      assert :binary.part(shadow, byte_size(shadow) - 3, 3) == "+ 1"
    end
  end

  describe "mask/1 — literal forms that used to leak into code" do
    # Both found 2026-08-18 while fixing the UTF-8 defects above. Each reproduced
    # this module's own first moduledoc example — FixPythonModulo rewriting
    # `100% done` inside a literal — so each is pinned end to end, not just at
    # the shadow.

    test "a sigil name may carry digits after the first letter" do
      # `~B64` and `~ABC123` are real sigils. Counting only letters stopped the
      # name at `B`, the delimiter check was handed `6`, the sigil went
      # unrecognised, and its whole body stood in the shadow as code.
      assert mask(~S|IO.puts(~B64(100% done))|) == "IO.puts(···············)"
      assert mask(~S|IO.puts(~ABC123(a div b))|) == "IO.puts(················)"
    end

    test "paired sigil delimiters nest without exposing their contents as code" do
      source = ~S|~s(outer (a % b) tail)|
      shadow = SourceMask.mask(source)

      assert show(shadow) == "······················"
      assert SourceMask.replace_code(source, shadow, "%", "DIV") == source

      assert SourceMask.replace_code("a % b", SourceMask.mask("a % b"), "%", "DIV") ==
               "a DIV b"
    end

    test "sigil modifiers are masked with the sigil" do
      source = ~S|~r/foo/iu|
      shadow = SourceMask.mask(source)

      assert show(shadow) == "·········"
      assert SourceMask.replace_code(source, shadow, "i", "X") == source
      assert SourceMask.replace_code("i = 1", SourceMask.mask("i = 1"), "i", "X") == "X = 1"
    end

    test "sigil-shaped things that are not sigils are still code" do
      assert mask(~S|a ~ b|) == "a ~ b"
      assert mask(~S|x = ~~~5|) == "x = ~~~5"
      assert mask(~S|x = ~s(a) <> ~r/b/|) == "x = ····· <> ·····"
    end

    test "`?\\u{` does not run to `}` and swallow a string's opening quote" do
      # The braced form is not an escape in Elixir 1.20 (`?\u` is the character
      # `u`), but it was scanned as one, running to `}` or end of line. In
      # `?\u{"a}b % 2" <> y` that ate the string's OPENING quote and released the
      # scanner into code state INSIDE the string.
      assert mask(~S|x = ?\u{"a}b % 2" <> y|) == "x = ···{········· <> y"
    end

    test "and a shipped rule no longer rewrites inside that string" do
      source = ~S|x = ?\u{"a}b % 2" <> y| <> "\n"

      assert Credence.Syntax.FixPythonModulo.fix(source) == source,
             "FixPythonModulo rewrote inside a string literal"
    end

    test "the same rule still repairs the real thing" do
      # The control. A mask that blanked everything would also pass the test
      # above, and prove nothing.
      source = "x = a % 2\n"

      assert Credence.Syntax.FixPythonModulo.fix(source) == "x = Integer.mod(a, 2)\n"
    end
  end

  describe "mask/1 — interpolation is code, and stays visible" do
    test "the interpolated expression survives, the delimiters do not" do
      assert mask(~S|x = "a#{b + 1}c"|) == "x = ····b + 1···"
    end

    test "brace depth is tracked, so a map inside interpolation finds its close" do
      assert mask(~S|x = "#{%{a: 1}}"|) == "x = ···%{a: 1}··"
    end

    test "an uppercase sigil does not interpolate, so its body stays masked" do
      assert mask(~S|x = ~S"#{no}"|) == "x = ·········"
    end

    test "a lowercase sigil does interpolate" do
      assert mask(~S|x = ~r/a#{b}/|) == "x = ······b··"
    end
  end

  describe "the blank byte, and which regex classes it is inert to" do
    # A rule author picks a pattern against this table. Getting it wrong is not
    # a compile error and not a test failure — it is a rule that silently spans
    # a literal, so the table is pinned rather than described.
    test "inert to the classes rules key on" do
      for {name, re} <- [{"\\w", ~r/\w/}, {"\\s", ~r/\s/}, {"\\d", ~r/\d/}] do
        refute Regex.match?(re, <<1>>), "#{name} matched the blank byte"
      end
    end

    test "NOT inert to \\S, . or a negated class" do
      # Not a defect — nothing can make a non-newline byte invisible to `.`.
      # It means a greedy `\S+` or `.+?` spans a literal in the shadow instead
      # of stopping at it, which is what `fix_div_rem.ex` relies on.
      for {name, re} <- [{"\\S", ~r/\S/}, {".", ~r/./}, {"[^\\n]", ~r/[^\n]/}] do
        assert Regex.match?(re, <<1>>), "#{name} no longer matches the blank byte"
      end
    end

    test "a greedy match spans a literal, and splices back byte-exactly" do
      line = ~S|IO.puts("a b") div 2|
      shadow = SourceMask.mask(line)

      [[_, {ls, ll}]] = Regex.scan(~r/(\S+\))\s+div/, shadow, return: :index)

      assert binary_part(line, ls, ll) == ~S|IO.puts("a b")|
    end
  end

  describe "self_contained?/2" do
    # A rule whose pattern keys on the delimiters themselves (`@doc "..."`, a
    # `~r/.../` sigil) cannot match the shadow — masking blanks the quotes it
    # is looking for. Those rules match the raw line and ask this instead.
    setup do
      source = ~S'''
      defmodule M do
        @moduledoc """
        x div 2
        """
        def f(n), do: n div 2
      end
      '''

      {:ok, lines: SourceMask.lines(source)}
    end

    test "true for ordinary code lines", %{lines: lines} do
      for i <- [0, 4, 5] do
        {line, shadow} = Enum.at(lines, i)
        assert SourceMask.self_contained?(line, shadow), "line #{i + 1}: #{inspect(line)}"
      end
    end

    test "true for the line that OPENS a heredoc", %{lines: lines} do
      # `@moduledoc """` masks the same alone as in the file: alone, the opener
      # is unterminated and the scanner blanks to end of input, which for one
      # line is the same three bytes.
      {line, shadow} = Enum.at(lines, 1)

      assert SourceMask.self_contained?(line, shadow)
    end

    test "false inside the heredoc body and on its terminator", %{lines: lines} do
      for i <- [2, 3] do
        {line, shadow} = Enum.at(lines, i)
        refute SourceMask.self_contained?(line, shadow), "line #{i + 1}: #{inspect(line)}"
      end
    end

    test "a line inside a multi-line plain string is not self-contained" do
      lines = SourceMask.lines("x = \"a\nb\"\ny = 1")

      refute lines |> Enum.at(1) |> then(fn {l, s} -> SourceMask.self_contained?(l, s) end)
      assert lines |> Enum.at(2) |> then(fn {l, s} -> SourceMask.self_contained?(l, s) end)
    end
  end

  describe "replace_code/5 — edits code bytes only" do
    defp one_line(source, pattern, replacement, opts \\ []) do
      [{line, shadow}] = SourceMask.lines(source)
      SourceMask.replace_code(line, shadow, pattern, replacement, opts)
    end

    test "replaces a plain call in code position" do
      assert one_line(~S|x = len(l)|, "len(", "length(") == ~S|x = length(l)|
    end

    test "leaves an identical match inside a string literal alone" do
      assert one_line(~S|x = {len(l), "call len(y)"}|, "len(", "length(") ==
               ~S|x = {length(l), "call len(y)"}|
    end

    test "leaves an identical match inside a trailing comment alone" do
      assert one_line(~S|x = len(l)  # len(y) was python|, "len(", "length(") ==
               ~S|x = length(l)  # len(y) was python|
    end

    test "leaves a match inside a sigil and a charlist alone" do
      assert one_line(~S|x = len(l) ++ ~c"len(z)"|, "len(", "length(") ==
               ~S|x = length(l) ++ ~c"len(z)"|
    end

    test "global: false stops after the first CODE match" do
      assert one_line(~S|len(a) + len(b)|, "len(", "length(", global: false) ==
               ~S|length(a) + len(b)|
    end

    test "global replaces every code match and no literal one" do
      assert one_line(~S|len(a) + len(b) + "len(c)"|, "len(", "length(") ==
               ~S|length(a) + length(b) + "len(c)"|
    end

    test "accepts a Regex, with the same literal-blindness" do
      re = Regex.compile!("(?<![.a-zA-Z0-9_])len\\(")

      assert one_line(~S|x = len(l) ; y = a.len(m) ; z = "len(n)"|, re, "length(") ==
               ~S|x = length(l) ; y = a.len(m) ; z = "len(n)"|
    end

    # The whole point of splicing rather than re-rendering: the bytes that were
    # not matched come back exactly as written, escapes and all.
    test "non-matched bytes survive verbatim" do
      src = ~S|x = len(l) <> "a\"b" <> ~S(raw \ stuff)|
      out = one_line(src, "len(", "length(")

      assert out == ~S|x = length(l) <> "a\"b" <> ~S(raw \ stuff)|
    end

    test "no code match is a no-op" do
      assert one_line(~S|x = "len(l)"|, "len(", "length(") == ~S|x = "len(l)"|
    end

    # A multi-line literal only shows up correctly when the WHOLE file is masked
    # — masking a line alone is the T3.7 `FixDivRem` defect.
    test "a heredoc body is protected because the file is masked, not the line" do
      source = """
      @doc \"\"\"
      call len(x) here
      \"\"\"
      """

      [_, {line, shadow} | _] = SourceMask.lines(source)

      assert SourceMask.replace_code(line, shadow, "len(", "length(") == line
    end
  end

  describe "byte_offset/3" do
    test "the first column of the first line is offset zero" do
      assert SourceMask.byte_offset("abc\ndef\n", 1, 1) == {:ok, 0}
    end

    test "counts the newline that ends each preceding line" do
      assert SourceMask.byte_offset("abc\ndef\n", 2, 1) == {:ok, 4}
      assert SourceMask.byte_offset("abc\ndef\n", 2, 3) == {:ok, 6}
    end

    test "one past the last character of a line is in range" do
      assert SourceMask.byte_offset("abc", 1, 4) == {:ok, 3}
    end

    test "out of range is :error rather than a wrong number" do
      assert SourceMask.byte_offset("abc\n", 9, 1) == :error
      assert SourceMask.byte_offset("abc\n", 1, 99) == :error
      assert SourceMask.byte_offset("abc\n", 1, 0) == :error
    end

    # The whole reason this returns bytes. The parser counts COLUMNS in graphemes, so
    # the conversion has to cross into byte space — and it must, because the shadow is
    # byte-aligned with the source and not grapheme-aligned.
    test "crosses from the parser's grapheme columns into byte space" do
      source = ~s|x = "héllo" + y|

      # `é` is two bytes, so every column after it is one byte further along than it
      # is columns along.
      assert SourceMask.byte_offset(source, 1, 15) == {:ok, 15}
      assert String.at(source, 14) == "y"
      assert :binary.at(source, 15) == ?y
    end

    # The invariant that makes a byte offset transferable to the shadow at all, and
    # the one a grapheme offset does NOT have. `WhenGuardPosition` went inert on every
    # file with a non-ASCII comment before this was understood.
    test "the shadow matches the source in bytes but not in graphemes" do
      for source <- [~s|x = "héllo"\n|, "# 🇵🇱 note\n", ~s|x = ~s(caf\u00e9)\n|] do
        shadow = SourceMask.mask(source)

        assert byte_size(shadow) == byte_size(source)
        assert String.length(shadow) > String.length(source)
      end
    end

    test "the offset it returns indexes the shadow and the source identically" do
      source = ~s|x = "héllo"\ny = 1\n|
      shadow = SourceMask.mask(source)
      {:ok, offset} = SourceMask.byte_offset(source, 2, 1)

      assert binary_part(source, offset, 1) == "y"
      assert binary_part(shadow, offset, 1) == "y"
    end
  end

  describe "blank?/1" do
    test "true for the fill byte, as a byte and as a one-byte binary" do
      shadow = SourceMask.mask(~s|x = "ab"|)

      assert SourceMask.blank?(:binary.at(shadow, 5))
      assert SourceMask.blank?(binary_part(shadow, 5, 1))
    end

    test "false for code bytes and for whitespace" do
      refute SourceMask.blank?(?x)
      refute SourceMask.blank?("x")
      refute SourceMask.blank?(?\s)
      refute SourceMask.blank?(?\n)
    end
  end

  describe "enclosing_opener/2" do
    defp opener(code, pos), do: SourceMask.enclosing_opener(SourceMask.mask(code), pos)

    test "reports the opener and which kind it is" do
      assert {:ok, 5, ?{} = opener("x = %{a: 1}", 8)
      assert {:ok, 4, ?[} = opener("x = [a, b]", 8)
      assert {:ok, 5, ?(} = opener("x = f(a, b)", 8)
    end

    # The point of walking BACK rather than taking the nearest opener: a pair that
    # closes before the position encloses nothing. Here the comma after `f(1, 2)` sits
    # in the map, not in the call.
    test "skips a bracket pair that closes before the position" do
      code = ~S|x = %{a: f(1, 2), "k" => 3}|

      assert :binary.at(code, 16) == ?,
      assert {:ok, 5, ?{} = opener(code, 16)
    end

    test "the innermost enclosing opener wins" do
      assert {:ok, 10, ?{} = opener(~S|x = %{a: %{b: 1}}|, 13)
    end

    test ":none at the top level and at position zero" do
      assert opener("x = 1", 4) == :none
      assert opener("x = 1", 0) == :none
    end

    # It must run on the shadow: a bracket inside a string is not a bracket. Given the
    # raw source this would report the `(` inside the literal.
    test "a bracket inside a string literal is not an opener" do
      assert opener(~S|x = "f(" <> y|, 12) == :none
    end
  end
end
