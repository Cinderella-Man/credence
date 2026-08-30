defmodule Credence.Syntax.FixForComprehensionInKeywordValueAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixForComprehensionInKeywordValue

  defp analyze(code), do: FixForComprehensionInKeywordValue.analyze(code)
  defp fix(code), do: FixForComprehensionInKeywordValue.fix(code)

  describe "flags a bare for comprehension used as a container value" do
    test "in a map" do
      code = "%{foo: for x <- [1, 2, 3], into: %{}, do: {x, x}}"

      assert [%Issue{rule: :fix_for_comprehension_in_keyword_value, meta: %{line: 1}}] =
               analyze(code)
    end

    test "in a keyword list" do
      code = "[foo: for x <- xs, into: %{}, do: {x, x}]"

      assert [%Issue{rule: :fix_for_comprehension_in_keyword_value}] = analyze(code)
    end

    test "in a tuple" do
      code = "{:ok, for x <- xs, do: x}"

      assert [%Issue{rule: :fix_for_comprehension_in_keyword_value}] = analyze(code)
    end

    test "spread over several lines" do
      code = """
      %{
        foo: for x <- xs,
             into: %{},
             do: {x, x}
      }
      """

      assert [%Issue{rule: :fix_for_comprehension_in_keyword_value, meta: %{line: 2}}] =
               analyze(code)
    end

    test "when a later pair on the same line also carries a `do:` key" do
      code = "%{foo: for x <- xs, do: x, bar: [do: 1]}"

      assert [%Issue{rule: :fix_for_comprehension_in_keyword_value}] = analyze(code)
    end

    test "once per pass, even with two comprehensions on one line" do
      code = "[a: for x <- xs, do: x, b: for y <- ys, do: y]"

      assert [%Issue{rule: :fix_for_comprehension_in_keyword_value}] = analyze(code)
    end

    test "on a line whose earlier text is multi-codepoint (grapheme columns)" do
      code = ~S'%{flag: "🇵🇱", family: "👨‍👩‍👧", accent: "é", foo: for x <- xs, do: x}'

      assert [%Issue{rule: :fix_for_comprehension_in_keyword_value}] = analyze(code)
    end
  end

  describe "no issue" do
    test "the comprehension is already parenthesized" do
      code = "%{foo: (for x <- [1, 2, 3], into: %{}, do: {x, x})}"

      assert analyze(code) == []
    end

    test "the source parses" do
      code = "%{foo: 1 + 2}"

      assert analyze(code) == []
    end

    test "a bare comprehension outside any container" do
      code = "for x <- [1, 2, 3], into: %{}, do: {x, x}"

      assert analyze(code) == []
    end

    # The same parse error covers every bare keyword-taking form in a
    # container. Wrapping from a column that does not hold `for` would corrupt
    # the line, so those belong to a sister rule, not to this one.
    test "the ambiguity is a bare `if`, not a comprehension" do
      code = "%{foo: if x > 0, do: :pos, else: :neg}"

      assert analyze(code) == []
    end

    test "the ambiguity is a bare `with`, even with the word `for` on the line" do
      code = ~S'%{a: "for", b: with {:ok, x} <- f(), do: x}'

      assert analyze(code) == []
    end

    # Nothing to close: without a `do:` the wrapped span would not be a
    # comprehension at all.
    test "the comprehension has no `do:` option" do
      code = "%{foo: for x <- xs, into: %{}}"

      assert analyze(code) == []
    end

    # A comment sits between the value and the container's `}`, so no candidate
    # end can be confirmed. Better to stay silent than to guess.
    test "the end of the comprehension cannot be confirmed" do
      code = """
      %{foo: for x <- xs, do: x
        # trailing note
      }
      """

      assert analyze(code) == []
    end

    test "the file is broken somewhere else entirely" do
      code = """
      defmodule M do
        def f(x), do: x
      """

      assert analyze(code) == []
    end
  end

  test "check and fix agree: exactly the flagged sources are the rewritten ones" do
    sources = [
      """
      %{foo: for x <- [1, 2, 3], into: %{}, do: {x, x}}
      """,
      """
      [foo: for x <- xs, into: %{}, do: {x, x}]
      """,
      """
      {:ok, for x <- xs, do: x}
      """,
      """
      %{
        foo: for x <- xs,
             into: %{},
             do: {x, x}
      }
      """,
      """
      %{foo: for x <- xs, do: x, bar: [do: 1]}
      """,
      """
      [a: for x <- xs, do: x, b: for y <- ys, do: y]
      """,
      """
      %{foo: (for x <- [1, 2, 3], into: %{}, do: {x, x})}
      """,
      """
      %{foo: 1 + 2}
      """,
      """
      for x <- [1, 2, 3], into: %{}, do: {x, x}
      """,
      """
      %{foo: if x > 0, do: :pos, else: :neg}
      """,
      """
      %{a: "for", b: with {:ok, x} <- f(), do: x}
      """,
      """
      %{foo: for x <- xs, into: %{}}
      """,
      """
      %{foo: for x <- xs, do: x
        # trailing note
      }
      """,
      """
      defmodule M do
        def f(x), do: x
      """
    ]

    for source <- sources do
      assert analyze(source) == [] == (fix(source) == source),
             "check and fix disagree on: #{inspect(source)}"
    end
  end
end
