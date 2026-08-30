defmodule Credence.Syntax.FixKeywordBlockAsFunctionArgFixTest do
  use ExUnit.Case, async: true

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixKeywordBlockAsFunctionArg

  defp analyze(code), do: FixKeywordBlockAsFunctionArg.analyze(code)
  defp fix(code), do: FixKeywordBlockAsFunctionArg.fix(code)

  describe "wraps the proven span" do
    test "keyword-syntax if as a later argument" do
      input = """
      defmodule M do
        def sort(list, desc?) do
          Enum.sort_by(list, & &1, if desc?, do: :desc, else: :asc)
        end
      end
      """

      expected = """
      defmodule M do
        def sort(list, desc?) do
          Enum.sort_by(list, & &1, (if desc?, do: :desc, else: :asc))
        end
      end
      """

      confirm_fix(fix(input), expected)
      assert analyze(fix(input)) == []
      assert valid_syntax?(fix(input))
    end

    test "keyword-syntax unless" do
      input = "f(a, unless c, do: 1, else: 2)"

      expected = "f(a, (unless c, do: 1, else: 2))"

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "if with do: and no else:" do
      input = "f(a, if c, do: 1)"

      expected = "f(a, (if c, do: 1))"

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "a comma inside a string does not cut the span short" do
      input = ~S'f(a, if c, do: "x", else: "y,z")'

      expected = ~S'f(a, (if c, do: "x", else: "y,z"))'

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "a closing paren inside a string does not cut the span short" do
      input = ~S'f(a, if c, do: 1, else: "y)z")'

      expected = ~S'f(a, (if c, do: 1, else: "y)z"))'

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "a closing paren inside a charlist sigil does not cut the span short" do
      input = ~S'f(a, if c, do: 1, else: ~c"y)z")'

      expected = ~S'f(a, (if c, do: 1, else: ~c"y)z"))'

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "map values whose own braces close inside the span" do
      input = "f(a, if c, do: %{k: 1}, else: %{})"

      expected = "f(a, (if c, do: %{k: 1}, else: %{}))"

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "a nested call carrying its own do: option" do
      input = "f(a, if c, do: 1, else: g(x, do: 2))"

      expected = "f(a, (if c, do: 1, else: g(x, do: 2)))"

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "a trailing comment is left where it was" do
      input = "f(a, if c, do: 1, else: 2) # note"

      expected = "f(a, (if c, do: 1, else: 2)) # note"

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "an else: written in a trailing comment does not move the closing paren" do
      input = "f(a, if c, do: 1, else: 2) # else: x"

      expected = "f(a, (if c, do: 1, else: 2)) # else: x"

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "whitespace before the closing bracket stays inside the parens" do
      input = "f(a, if c, do: 1, else: 2 )"

      expected = "f(a, (if c, do: 1, else: 2 ))"

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end
  end

  describe "repeats until the file is repaired" do
    test "two broken calls on separate lines" do
      input = """
      f(a, if c, do: 1, else: 2)
      g(b, if d, do: 3, else: 4)
      """

      expected = """
      f(a, (if c, do: 1, else: 2))
      g(b, (if d, do: 3, else: 4))
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "two broken calls on one line" do
      input = "f(a, if c, do: 1, else: 2) + f(b, if d, do: 3, else: 4)"

      expected = "f(a, (if c, do: 1, else: 2)) + f(b, (if d, do: 3, else: 4))"

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "more than twenty broken calls" do
      calls = Enum.map_join(1..21, "\n", fn n -> "f(a#{n}, if c#{n}, do: 1, else: 2)" end)

      expected_calls =
        Enum.map_join(1..21, "\n", fn n -> "f(a#{n}, (if c#{n}, do: 1, else: 2))" end)

      input = """
      defmodule KeywordBlockTwentyOneCallsEmitted do
        def run(#{Enum.map_join(1..21, ", ", &"a#{&1}")}, #{Enum.map_join(1..21, ", ", &"c#{&1}")}) do
      #{calls}
        end

        defp f(value, direction), do: {value, direction}
      end
      """

      expected = String.replace(input, calls, expected_calls)
      emitted = fix(input)

      confirm_fix(emitted, expected)
      assert analyze(emitted) == []
      assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(emitted)

      control =
        String.replace(
          expected,
          "KeywordBlockTwentyOneCallsEmitted",
          "KeywordBlockTwentyOneCallsControl"
        )

      assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(control)
    end
  end

  describe "columns are counted in graphemes" do
    test "a precomposed accented character earlier on the line" do
      input = ~S'f("café", if c, do: 1, else: 2)'

      expected = ~S'f("café", (if c, do: 1, else: 2))'

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "a combining accent earlier on the line" do
      input = ~S'f("café", if c, do: 1, else: 2)'

      expected = ~S'f("café", (if c, do: 1, else: 2))'

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "a multi-codepoint emoji earlier on the line" do
      input = ~S'f("👨‍👩‍👧‍👦", if c, do: 1, else: 2)'

      expected = ~S'f("👨‍👩‍👧‍👦", (if c, do: 1, else: 2))'

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "a flag emoji earlier on the line" do
      input = ~S'f("🇵🇱", if c, do: 1, else: 2)'

      expected = ~S'f("🇵🇱", (if c, do: 1, else: 2))'

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end
  end

  describe "leaves alone" do
    test "the same parser error raised by something that is not an if" do
      code = "f(a, b c, d)"

      confirm_fix(fix(code), code)
    end

    test "a stray else: in a trailing comment cannot make a non-if look like one" do
      code = "f(a, b c, d) # else: boom"

      confirm_fix(fix(code), code)
    end

    test "an identifier that merely starts with if" do
      code = "f(a, iffy c, d)"

      confirm_fix(fix(code), code)
    end

    test "the with-clause shape belongs to a sister rule" do
      code = """
      with a <- 1,
           b <- if c, do: 1, else: 2 do
        b
      end
      """

      confirm_fix(fix(code), code)
    end

    test "an if continued on the next line" do
      code = """
      f(a,
        if c, do: 1,
        else: 2)
      """

      confirm_fix(fix(code), code)
    end

    test "an else: value continued on the next line" do
      code = """
      f(a, if c, do: 1, else:
        2)
      """

      confirm_fix(fix(code), code)
    end

    test "another argument after the if" do
      code = "f(a, if c, do: 1, else: 2, b)"

      confirm_fix(fix(code), code)
    end

    test "source that already parses" do
      code = """
      defmodule M do
        def sort(list, desc?) do
          Enum.sort_by(list, & &1, (if desc?, do: :desc, else: :asc))
        end
      end
      """

      confirm_fix(fix(code), code)
    end

    test "an if written as a do block" do
      code = "f(a, if c do 1 else 2 end)"

      confirm_fix(fix(code), code)
    end

    test "empty source" do
      confirm_fix(fix(""), "")
    end
  end
end
