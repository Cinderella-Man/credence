defmodule Credence.Syntax.WhenGuardPositionTest do
  use ExUnit.Case, async: true

  alias Credence.Syntax.WhenGuardPosition

  # The shared locator, tested directly rather than only through
  # `FixMisplacedWhenGuard`. It is the half that decides which of two OPPOSITE repairs
  # applies, so its mistakes are silent: both repairs parse, and picking wrong yields
  # code that compiles and means something else.

  defp locate(code), do: WhenGuardPosition.locate(code)

  # The offset is what the rule deletes at, so assert on the character it points to
  # rather than on a number that would have to be recounted whenever a fixture moves.
  defp at(code, offset), do: String.slice(code, offset, 1)

  describe "clause heads — the comma is the mistake" do
    test "def, pointing at the comma and not the when" do
      code = "def positive?(x), when x > 0, do: true"

      assert {:ok, :clause_head, offset} = locate(code)
      assert at(code, offset) == ","
      assert offset == 16
    end

    for {label, code} <- [
          {"defp", "defp ok?(x), when is_atom(x), do: true\n"},
          {"defmacro", "defmacro m(x), when is_atom(x), do: x\n"},
          {"defmacrop", "defmacrop m(x), when is_atom(x), do: x\n"},
          {"case", "case x do\n  y, when y > 0 -> y\nend\n"},
          {"fn", "fn y, when y > 0 -> y end\n"}
        ] do
      test label do
        code = unquote(code)

        assert {:ok, :clause_head, offset} = locate(code)
        assert at(code, offset) == ","
      end
    end

    # The comma is on the previous line. `preceding_comma/2` walks back over newlines
    # for exactly this, and the offset is absolute so the caller needs no line math.
    test "split across lines" do
      code = """
      def f(x),
        when x > 0,
        do: x
      """

      assert {:ok, :clause_head, offset} = locate(code)
      assert at(code, offset) == ","
      assert offset == 8
    end
  end

  describe "for filters — the when is the mistake" do
    test "pointing at the w of when" do
      code = """
      for {name, price} <- items, when price > 100 do
        name
      end
      """

      assert {:ok, :for_filter, offset} = locate(code)
      assert String.slice(code, offset, 5) == "when "
    end

    # The bracket-depth fold is what earns this. A naive "last keyword before the
    # error" scan would see `f()`'s own tokens; a naive "is the previous char a `)`"
    # heuristic would call it a clause head and delete the comma, which does not
    # compile for `for`.
    test "a generator ending in a call is still a for" do
      code = """
      for a <- f(), when a > 1 do
        a
      end
      """

      assert {:ok, :for_filter, offset} = locate(code)
      assert String.slice(code, offset, 4) == "when"
    end

    test "a generator whose pattern contains brackets" do
      assert {:ok, :for_filter, _} = locate("for {a, [b]} <- l, when b > 1, do: a\n")
    end

    # The nearest enclosing keyword wins, so a `for` inside a `def` body resolves to
    # the `for` — the interleaving that a per-shape rule could not handle.
    test "a for nested inside a def body" do
      code = """
      def g(l) do
        for a <- l, when a > 1 do
          a
        end
      end
      """

      assert {:ok, :for_filter, offset} = locate(code)
      assert String.slice(code, offset, 4) == "when"
    end
  end

  describe "declines" do
    test "source that parses" do
      assert locate("def f(x) when x > 0, do: x\n") == :none
    end

    test "a valid when in a generator pattern" do
      assert locate("for {a, b} when b > 1 <- list, do: a\n") == :none
    end

    # Neither repair preserves intent here — deleting the comma does not compile, and
    # deleting the `when` compiles while silently dropping the guard. The moduledoc
    # carries the execution; this pins the disposition.
    test "with, where neither repair is correct" do
      assert locate("with {:ok, x} <- f(), when x > 0 do\n  x\nend\n") == :none
    end

    for {label, code} <- [
          {"receive", "receive do\n  x, when x > 0 -> x\nend\n"},
          {"try", "try do\n  f()\nrescue\n  e, when true -> e\nend\n"},
          {"cond", "cond do\n  x, when x > 0 -> 1\nend\n"}
        ] do
      # Present in `@keywords` so they cannot be mistaken for an enclosing `def` or
      # `for`, but absent from both repair lists: the repair is plausible and was
      # never executed, and a wrong guess here is silent.
      test "#{label}, whose repair is unverified" do
        assert locate(unquote(code)) == :none
      end
    end

    test "an unrelated syntax error" do
      assert locate("x = foo((1\n") == :none
    end

    test "a clause head with no comma before the when" do
      assert locate("x = 1 when\n") == :none
    end
  end

  # The scan runs on `SourceMask.mask/1`'s shadow, so a `when` in a string, heredoc,
  # sigil or comment is invisible. Each fixture also carries an UNRELATED parse error,
  # because without one the file parses and `locate/1` would decline for that reason
  # instead — the decoy would never be reached and the test would prove nothing.
  describe "ignores when inside strings, comments and sigils" do
    for {label, code} <- [
          {"a string", "x = \"a, when b\"\ny = (\n"},
          {"a comment", "# a, when b\ny = (\n"},
          {"a heredoc", "x = \"\"\"\na, when b\n\"\"\"\n\ny = (\n"},
          {"a sigil", "x = ~s(a, when b)\ny = (\n"},
          {"a charlist", "x = ~c\"a, when b\"\ny = (\n"}
        ] do
      test label do
        assert locate(unquote(code)) == :none
      end
    end

    # The decoy must not steer a REAL defect either, and to test that it has to sit
    # BETWEEN the clause head and the `when` — a decoy after the error is never
    # reached, since the scan only ever walks backwards from it.
    #
    # On the raw source this comment would do two things, both wrong: `last_keyword`
    # would find its `for` nearer than the real `def` and return :for_filter, which
    # deletes the `when` and yields `def f(x), x > 0`; and `preceding_comma` would
    # find the comment's own trailing comma. On the shadow the comment is blanked,
    # so neither is visible and the real comma one line up is what is found.
    # Every offset is a BYTE offset, and it has to be: `mask/1` promises the shadow is
    # the same number of BYTES, not the same number of graphemes. Computing grapheme
    # offsets from the source and indexing the shadow with them drifted one position
    # per extra byte, and the measured result was `:none` — the rule went inert on any
    # file with a non-ASCII comment or string rather than corrupting one, so no gate
    # could see it. See `SourceMask.byte_offset/3`.
    test "a multi-byte character earlier in the file does not shift the verdict" do
      for prefix <- [
            ~s|x = "héllo"\n|,
            "# 🇵🇱 note\n",
            "# ZWJ 👩‍👩‍👧 family\n",
            ~s|x = ~s(café)\n|
          ] do
        code = prefix <> "def f(x), when x > 0, do: x\n"

        assert {:ok, :clause_head, offset} = locate(code)
        assert binary_part(code, offset, 1) == ","
      end
    end

    test "a decoy for inside a comment does not reclassify a real clause head" do
      code = """
      def f(x), # for a <- l,
        when x > 0, do: x
      """

      assert {:ok, :clause_head, offset} = locate(code)
      assert at(code, offset) == ","
      assert offset == 8
    end
  end
end
