defmodule Credence.Syntax.NoKeywordIfBareInTupleAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoKeywordIfBareInTuple

  defp analyze(code), do: NoKeywordIfBareInTuple.analyze(code)
  defp fix(code), do: NoKeywordIfBareInTuple.fix(code)

  describe "flags a bare keyword-syntax conditional inside a container" do
    test "in a tuple, reporting the line the parser blamed" do
      code = """
      defmodule M do
        def parse_page(params) do
          case Integer.parse(params) do
            {num, _} -> {:ok, if num < 1, do: 1, else: num}
            :error -> {:ok, 1}
          end
        end
      end
      """

      assert [%Issue{rule: :no_keyword_if_bare_in_tuple, meta: %{line: 4}}] = analyze(code)
    end

    test "with only a do: branch" do
      code = "{:ok, if a, do: 1}"

      assert [%Issue{rule: :no_keyword_if_bare_in_tuple}] = analyze(code)
    end

    test "written as unless" do
      code = "{:ok, unless a, do: 1, else: 2}"

      assert [%Issue{rule: :no_keyword_if_bare_in_tuple}] = analyze(code)
    end

    test "in a list" do
      code = "[1, if a, do: 2, else: 3]"

      assert [%Issue{rule: :no_keyword_if_bare_in_tuple}] = analyze(code)
    end

    test "as a map value" do
      code = "%{k: 1, v: if a, do: 2, else: 3}"

      assert [%Issue{rule: :no_keyword_if_bare_in_tuple}] = analyze(code)
    end

    test "spread over several lines" do
      code = """
      x = {:ok,
        if a,
          do: 1,
          else: 2}
      """

      assert [%Issue{rule: :no_keyword_if_bare_in_tuple, meta: %{line: 2}}] = analyze(code)
    end
  end

  describe "no issue" do
    test "when the source already parses" do
      code = """
      defmodule M do
        def parse_page(params) do
          case Integer.parse(params) do
            {num, _} -> {:ok, (if num < 1, do: 1, else: num)}
            :error -> {:ok, 1}
          end
        end
      end
      """

      assert analyze(code) == []
    end

    test "when the same ambiguity is blamed on a plain call, not a conditional" do
      code = "{:ok, foo a, b: 1}"

      assert analyze(code) == []
    end

    test "when the ambiguous container value is a bare for comprehension" do
      # FixForComprehensionInKeywordValue owns this shape; wrapping from a
      # column that does not hold `if` would corrupt the line.
      code = "%{foo: for x <- xs, into: %{}, do: {x, x}}"

      assert analyze(code) == []
    end

    test "when the ambiguous container value is a bare with" do
      code = "{:ok, with {:ok, x} <- f(), do: x}"

      assert analyze(code) == []
    end

    test "when the conditional is a nested call argument, not a container value" do
      # A different parse error ("ambiguity in nested calls") with a different
      # owner; this rule keys off the container message only.
      code = "f(1, if a, do: 2, else: 3)"

      assert analyze(code) == []
    end

    test "when the blamed column holds an identifier that merely starts with if" do
      code = "{:ok, iffy a, b: 1}"

      assert analyze(code) == []
    end

    test "when a comment separates the do: value from the else:" do
      # The only span the parser accepts here stops after `do: 1`, which would
      # demote `else: 2` to a third tuple element. Left alone on purpose.
      code = """
      {:ok, if a, do: 1, else: 2 # note
      }
      """

      assert analyze(code) == []
    end

    test "when the conditional ends beyond the search window" do
      filler = String.duplicate("    # filler\n", 25)

      code = "x = {:ok,\n  if a,\n" <> filler <> "    do: 1,\n    else: 2}\n"

      assert analyze(code) == []
    end

    test "when the parse error is something else entirely" do
      code = """
      defmodule M do
        def f do
      end
      """

      assert analyze(code) == []
    end

    test "for text that only looks like the shape inside a heredoc" do
      code = """
      x = \"\"\"
      {:ok, if a, do: 1, else: 2}
      \"\"\"
      y = {
      """

      assert analyze(code) == []
    end
  end

  describe "check and fix agree" do
    @samples [
      "{:ok, if num < 1, do: 1, else: num}\n",
      "{:ok, if a, do: 1}\n",
      "{:ok, unless a, do: 1, else: 2}\n",
      "[1, if a, do: 2, else: 3]\n",
      "%{k: 1, v: if a, do: 2, else: 3}\n",
      "{:ok, if a, do: 1, else: \"}\"}\n",
      "{:ok, foo a, b: 1}\n",
      "%{foo: for x <- xs, into: %{}, do: {x, x}}\n",
      "{:ok, with {:ok, x} <- f(), do: x}\n",
      "f(1, if a, do: 2, else: 3)\n",
      "{:ok, iffy a, b: 1}\n",
      "{:ok, if a, do: 1, else: 2 # note\n}\n",
      "{:ok, (if a, do: 1, else: 2)}\n",
      "defmodule M do\n  def f do\nend\n"
    ]

    test "every sample is flagged exactly when the fix rewrites it" do
      for sample <- @samples do
        assert analyze(sample) != [] == (fix(sample) != sample),
               "check/fix disagree on #{inspect(sample)}"
      end
    end
  end
end
