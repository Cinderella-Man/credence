defmodule Credence.Syntax.FixForComprehensionInKeywordValueFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixForComprehensionInKeywordValue

  defp analyze(code), do: FixForComprehensionInKeywordValue.analyze(code)
  defp fix(code), do: FixForComprehensionInKeywordValue.fix(code)

  describe "wraps the comprehension" do
    test "in a map" do
      code = "%{foo: for x <- [1, 2, 3], into: %{}, do: {x, x}}"

      expected = "%{foo: (for x <- [1, 2, 3], into: %{}, do: {x, x})}"

      confirm_fix(fix(code), expected)
    end

    test "in a keyword list" do
      code = "[foo: for x <- xs, into: %{}, do: {x, x}]"

      expected = "[foo: (for x <- xs, into: %{}, do: {x, x})]"

      confirm_fix(fix(code), expected)
    end

    test "in a tuple" do
      code = "{:ok, for x <- xs, do: x}"

      expected = "{:ok, (for x <- xs, do: x)}"

      confirm_fix(fix(code), expected)
    end

    test "once per occurrence, several in one module" do
      code = """
      defmodule M do
        def build(final) do
          %{
            metrics: %{
              processed: for {id, {p, _}} <- final, into: %{}, do: {id, p},
              steals: for {id, {_, s}} <- final, into: %{}, do: {id, s}
            }
          }
        end
      end
      """

      expected = """
      defmodule M do
        def build(final) do
          %{
            metrics: %{
              processed: (for {id, {p, _}} <- final, into: %{}, do: {id, p}),
              steals: (for {id, {_, s}} <- final, into: %{}, do: {id, s})
            }
          }
        end
      end
      """

      confirm_fix(fix(code), expected)
    end

    test "spread over several lines" do
      code = """
      %{
        foo: for x <- xs,
             into: %{},
             do: {x, x}
      }
      """

      expected = """
      %{
        foo: (for x <- xs,
             into: %{},
             do: {x, x})
      }
      """

      confirm_fix(fix(code), expected)
    end

    test "when a newline follows the for keyword" do
      code = """
      %{foo: for
        x <- xs, do: x}
      """

      expected = """
      %{foo: for(
        x <- xs, do: x)}
      """

      fixed = fix(code)

      confirm_fix(fixed, expected)
      assert valid_syntax?(fixed)
      assert valid_syntax?(expected)
    end
  end

  describe "places the closing paren at the end of the comprehension" do
    # A brace-counting walk would stop at the comma inside the string and cut
    # the literal in half.
    test "past a comma inside a string literal" do
      code = ~S'%{foo: for x <- xs, do: "a, b"}'

      expected = ~S'%{foo: (for x <- xs, do: "a, b")}'

      confirm_fix(fix(code), expected)
    end

    # The `do:` inside `bar:` belongs to the map, not to the comprehension.
    test "before a later pair that also carries a `do:` key" do
      code = "%{foo: for x <- xs, do: x, bar: [do: 1]}"

      expected = "%{foo: (for x <- xs, do: x), bar: [do: 1]}"

      confirm_fix(fix(code), expected)
    end

    test "around each of two comprehensions on one line" do
      code = "[a: for x <- xs, do: x, b: for y <- ys, do: y]"

      expected = "[a: (for x <- xs, do: x), b: (for y <- ys, do: y)]"

      confirm_fix(fix(code), expected)
    end

    # Cutting after the `x` would turn the body `x + 1` into `(for …) + 1`.
    test "after a `do:` body that continues past the first operand" do
      code = "%{foo: for x <- xs, do: x + 1}"

      expected = "%{foo: (for x <- xs, do: x + 1)}"

      confirm_fix(fix(code), expected)
    end

    # Same trap, with the continuation on the next line.
    test "after a `do:` body continued by a leading pipe on the next line" do
      code = """
      %{foo: for x <- xs,
         do: x
         |> f()}
      """

      expected = """
      %{foo: (for x <- xs,
         do: x
         |> f())}
      """

      confirm_fix(fix(code), expected)
    end

    test "on a line whose earlier text is multi-codepoint (grapheme columns)" do
      code = ~S'%{flag: "🇵🇱", family: "👨‍👩‍👧", accent: "é", foo: for x <- xs, do: x}'

      expected = ~S'%{flag: "🇵🇱", family: "👨‍👩‍👧", accent: "é", foo: (for x <- xs, do: x)}'

      confirm_fix(fix(code), expected)
    end
  end

  describe "leaves the source untouched" do
    test "when the comprehension is already parenthesized" do
      code = "%{foo: (for x <- [1, 2, 3], into: %{}, do: {x, x})}"

      confirm_fix(fix(code), code)
    end

    test "when the source parses" do
      code = "%{foo: 1 + 2}"

      confirm_fix(fix(code), code)
    end

    test "when the ambiguity is a bare `if`, not a comprehension" do
      code = "%{foo: if x > 0, do: :pos, else: :neg}"

      confirm_fix(fix(code), code)
    end

    test "when the ambiguity is a bare `with`, even with the word `for` on the line" do
      code = ~S'%{a: "for", b: with {:ok, x} <- f(), do: x}'

      confirm_fix(fix(code), code)
    end

    test "when the comprehension has no `do:` option" do
      code = "%{foo: for x <- xs, into: %{}}"

      confirm_fix(fix(code), code)
    end

    test "when the end of the comprehension cannot be confirmed" do
      code = """
      %{foo: for x <- xs, do: x
        # trailing note
      }
      """

      confirm_fix(fix(code), code)
    end

    test "when the file is broken somewhere else entirely" do
      code = """
      defmodule M do
        def f(x), do: x
      """

      confirm_fix(fix(code), code)
    end
  end

  test "the fixed source parses and no longer flags" do
    code = """
    %{
      metrics: %{
        processed: for {id, p} <- final, into: %{}, do: {id, p},
        totals: for x <- xs, do: x + 1,
        labels: for x <- xs, do: "a, b"
      }
    }
    """

    assert valid_syntax?(fix(code))
    assert analyze(fix(code)) == []
  end
end
