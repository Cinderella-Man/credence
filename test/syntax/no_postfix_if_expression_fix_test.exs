defmodule Credence.Syntax.NoPostfixIfExpressionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [compiles?: 1, confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoPostfixIfExpression

  defp analyze(code), do: NoPostfixIfExpression.analyze(code)
  defp fix(code), do: NoPostfixIfExpression.fix(code)

  test "fixes the syntax error" do
    input = """
    defmodule Trend do
      def update(current_max, period, type) do
        new_max = current_max
        new_max = max(current_max, period) if type == :sma
        new_max
      end
    end
    """

    expected = """
    defmodule Trend do
      def update(current_max, period, type) do
        new_max = current_max
        new_max = if type == :sma, do: max(current_max, period), else: new_max
        new_max
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes an indented accumulator rebinding" do
    input = """
    Enum.reduce(list, 0, fn x, total ->
      total = total + 1 if x > 0
      total
    end)
    """

    expected = """
    Enum.reduce(list, 0, fn x, total ->
      total = if x > 0, do: total + 1, else: total
      total
    end)
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = """
    defmodule Trend do
      def update(current_max, period, type) do
        new_max = current_max
        new_max = max(current_max, period) if type == :sma
        new_max
      end
    end
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Trend do
      def update(current_max, period, type) do
        new_max = current_max
        new_max = max(current_max, period) if type == :sma
        new_max
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "fixed output compiles — the `else:` branch names a real binding" do
    input = """
    defmodule Trend do
      def update(current_max, period, type) do
        new_max = current_max
        new_max = max(current_max, period) if type == :sma
        new_max
      end
    end
    """

    assert compiles?(fix(input))
  after
    :code.purge(Trend)
    :code.delete(Trend)
  end

  # --- everything below must come back byte-identical ---

  test "no-op: a string literal containing ` if `" do
    code = """
    defmodule M do
      def run do
        msg = "start"
        msg = "run if you can"
        x = [1, 2
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "no-op: a comment containing ` if `" do
    code = """
    defmodule M do
      def run do
        foo = 1
        foo = bar() # only if needed
        x = [1, 2
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "no-op: a valid keyword-form `if` with extra spacing" do
    code = """
    x = 0
    x =  if cond?, do: 1, else: 2
    """

    confirm_fix(fix(code), code)
  end

  test "no-op: a Python conditional expression with `else`" do
    code = """
    label = ""
    label = "yes" if a else "no"
    """

    confirm_fix(fix(code), code)
  end

  test "no-op: two chained `if` modifiers" do
    code = """
    x = 0
    x = a if b if c
    """

    confirm_fix(fix(code), code)
  end

  test "no-op: a parenless call whose arguments would swallow the `else:`" do
    code = """
    x = 0
    x = foo a, b if c
    """

    confirm_fix(fix(code), code)
  end

  test "no-op: an expression ending in a bare identifier — the line parses" do
    code = """
    total = 0
    total = total + x if x > 0
    """

    confirm_fix(fix(code), code)
  end

  test "no-op: a trailing comment after the condition" do
    code = """
    x = 0
    x = foo() if bar # note
    """

    confirm_fix(fix(code), code)
  end

  test "no-op: a unicode variable name" do
    code = """
    café = 0
    café = compute(a) if flag
    """

    confirm_fix(fix(code), code)
  end

  test "no-op: two statements on the line" do
    code = """
    x = 0
    x = a; b if c
    """

    confirm_fix(fix(code), code)
  end

  test "no-op: the variable is not bound earlier in the file" do
    code = "new_max = max(current_max, period) if type == :sma"

    confirm_fix(fix(code), code)
  end

  test "no-op: the variable appears earlier only in a comment" do
    code = """
    defmodule NoPostfixIfCommentBindingFixture do
      def run(flag) do
        # x was discussed here
        x = foo() if flag
        x
      end

      defp foo, do: 1
    end
    """

    confirm_fix(fix(code), code)
  end

  test "no-op: the variable is bound only in another function" do
    code = """
    defmodule NoPostfixIfOtherFunctionBindingFixture do
      def first do
        x = 1
        x
      end

      def second(flag) do
        x = foo() if flag
        x
      end

      defp foo, do: 1
    end
    """

    confirm_fix(fix(code), code)
  end

  test "no-op: a documentation example inside a heredoc" do
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

    confirm_fix(fix(code), code)
  end

  test "no-op: postfix-looking text inside a charlist heredoc" do
    code = """
    defmodule NoPostfixIfCharlistHeredocFixture do
      def run do
        x = 0

        ~c'''
        x = foo() if flag
        '''
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "no-op: an unterminated string that happens to contain ` if `" do
    code = """
    x = 0
    x = "unterminated if c
    """

    confirm_fix(fix(code), code)
  end
end
