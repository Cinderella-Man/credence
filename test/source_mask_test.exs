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

    test "character literals, including their numeric escapes" do
      # `?\x41` masked whole, so `41` cannot survive as a word token and get
      # rewritten mid-literal by a rule looking for digits.
      assert mask(~S|x = ?a + ?\x41|) == "x = ·· + ·····"
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
end
