defmodule Credence.Syntax.NoPostfixIfExpressionAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoPostfixIfExpression

  defp analyze(code), do: NoPostfixIfExpression.analyze(code)

  test "flags a postfix `if` rebinding an existing variable" do
    code = """
    defmodule Trend do
      def update(current_max, period, type) do
        new_max = current_max
        new_max = max(current_max, period) if type == :sma
        new_max
      end
    end
    """

    assert [%Issue{rule: :no_postfix_if_expression, meta: %{line: 4}}] = analyze(code)
  end

  test "flags an indented accumulator rebinding" do
    code = """
    Enum.reduce(list, 0, fn x, total ->
      total = total + 1 if x > 0
      total
    end)
    """

    assert [%Issue{rule: :no_postfix_if_expression, meta: %{line: 2}}] = analyze(code)
  end

  test "leaves the valid keyword form alone" do
    assert analyze("new_max = if type == :sma, do: max(current_max, period), else: current_max") ==
             []
  end

  # --- deliberately not flagged: the whole file is handed to every syntax rule,
  # so a line that merely *looks* like a postfix `if` must survive untouched ---

  test "no issue: a string literal containing ` if `" do
    code = """
    defmodule M do
      def run do
        msg = "start"
        msg = "run if you can"
        x = [1, 2
      end
    end
    """

    assert analyze(code) == []
  end

  test "no issue: a comment containing ` if `" do
    code = """
    defmodule M do
      def run do
        foo = 1
        foo = bar() # only if needed
        x = [1, 2
      end
    end
    """

    assert analyze(code) == []
  end

  test "no issue: a valid keyword-form `if` with extra spacing" do
    code = """
    x = 0
    x =  if cond?, do: 1, else: 2
    """

    assert analyze(code) == []
  end

  test "no issue: a Python conditional expression with `else`" do
    code = """
    label = ""
    label = "yes" if a else "no"
    """

    assert analyze(code) == []
  end

  test "no issue: two chained `if` modifiers" do
    code = """
    x = 0
    x = a if b if c
    """

    assert analyze(code) == []
  end

  test "no issue: a parenless call whose arguments would swallow the `else:`" do
    code = """
    x = 0
    x = foo a, b if c
    """

    assert analyze(code) == []
  end

  test "no issue: an expression ending in a bare identifier — the line parses" do
    # `total + x if x > 0` parses as `total + x(if(x > 0))`, so this is not a
    # syntax error at all; rewriting a line that parses is never this phase's job.
    code = """
    total = 0
    total = total + x if x > 0
    """

    assert analyze(code) == []
  end

  test "no issue: a trailing comment after the condition" do
    # The comment would swallow the generated `, do: ..., else: ...`, so gate 5
    # (re-parse the rewrite) throws the match away.
    code = """
    x = 0
    x = foo() if bar # note
    """

    assert analyze(code) == []
  end

  test "no issue: two statements on the line" do
    code = """
    x = 0
    x = a; b if c
    """

    assert analyze(code) == []
  end

  test "no issue: the variable is not bound earlier in the file" do
    assert analyze("new_max = max(current_max, period) if type == :sma") == []
  end

  test "no issue: a documentation example inside a heredoc" do
    # `new_max` is bound before the heredoc, so only the heredoc gate keeps the
    # documentation line — which is prose, not code — from being rewritten.
    code = """
    defmodule M do
      def run do
        new_max = 0

        IO.puts(\"\"\"
        Python spells the update as

            new_max = max(current_max, period) if type == :sma
        \"\"\")

        x = [1, 2
      end
    end
    """

    assert analyze(code) == []
  end
end
