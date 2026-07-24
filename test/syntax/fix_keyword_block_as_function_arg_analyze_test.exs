defmodule Credence.Syntax.FixKeywordBlockAsFunctionArgAnalyzeTest do
  use ExUnit.Case, async: true

  alias Credence.Issue
  alias Credence.Syntax.FixKeywordBlockAsFunctionArg

  defp analyze(code), do: FixKeywordBlockAsFunctionArg.analyze(code)

  describe "flags the proven shape" do
    test "keyword-syntax if as a later argument" do
      code = """
      defmodule M do
        def sort(list, desc?) do
          Enum.sort_by(list, & &1, if desc?, do: :desc, else: :asc)
        end
      end
      """

      assert [%Issue{rule: :fix_keyword_block_as_function_arg, meta: %{line: 3}}] = analyze(code)
    end

    test "keyword-syntax unless as a later argument" do
      code = """
      defmodule M do
        def go(a, c) do
          f(a, unless c, do: 1, else: 2)
        end
      end
      """

      assert [%Issue{rule: :fix_keyword_block_as_function_arg, meta: %{line: 3}}] = analyze(code)
    end

    test "if with do: and no else:" do
      code = "f(a, if c, do: 1)"

      assert [%Issue{rule: :fix_keyword_block_as_function_arg, meta: %{line: 1}}] = analyze(code)
    end

    test "a bracket inside the else: value does not hide the span" do
      code = ~S'f(a, if c, do: 1, else: "y)z")'

      assert [%Issue{rule: :fix_keyword_block_as_function_arg, meta: %{line: 1}}] = analyze(code)
    end
  end

  describe "no issue" do
    test "the already-parenthesised form" do
      code = """
      defmodule M do
        def sort(list, desc?) do
          Enum.sort_by(list, & &1, (if desc?, do: :desc, else: :asc))
        end
      end
      """

      assert analyze(code) == []
    end

    test "an if written as a do block parses, so nothing is reported" do
      code = "f(a, if c do 1 else 2 end)"

      assert analyze(code) == []
    end

    test "the same parser error raised by something that is not an if" do
      code = "f(a, b c, d)"

      assert analyze(code) == []
    end

    test "a stray else: in a trailing comment cannot make a non-if look like one" do
      code = "f(a, b c, d) # else: boom"

      assert analyze(code) == []
    end

    test "an identifier that merely starts with if" do
      code = "f(a, iffy c, d)"

      assert analyze(code) == []
    end

    test "the with-clause shape belongs to a sister rule" do
      code = """
      with a <- 1,
           b <- if c, do: 1, else: 2 do
        b
      end
      """

      assert analyze(code) == []
    end

    test "an if continued on the next line has no provable span" do
      code = """
      f(a,
        if c, do: 1,
        else: 2)
      """

      assert analyze(code) == []
    end

    test "an else: value continued on the next line has no provable span" do
      code = """
      f(a, if c, do: 1, else:
        2)
      """

      assert analyze(code) == []
    end

    test "another argument after the if is left to the parser" do
      code = "f(a, if c, do: 1, else: 2, b)"

      assert analyze(code) == []
    end

    test "source that already parses" do
      code = """
      defmodule M do
        def go(a), do: f(a)
      end
      """

      assert analyze(code) == []
    end

    test "empty source" do
      assert analyze("") == []
    end
  end
end
