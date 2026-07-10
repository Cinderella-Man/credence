defmodule Credence.Semantic.FixRaiseInKeywordValueFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixRaiseInKeywordValue

  @diagnostic_msg "missing parentheses for expression following \"do:\" keyword. Parentheses are required to solve ambiguity inside keywords.\n\nThis error happens when you have function calls without parentheses inside keywords. For example:\n\n    function(arg, one: nested_call a, b, c)\n    function(arg, one: if expr, do: :this, else: :that)\n\nIn the examples above, we don't know if the arguments \"b\" and \"c\" apply to the function \"function\" or \"nested_call\". Or if the keywords \"do\" and \"else\" apply to the function \"function\" or \"if\". You can solve this by explicitly adding parentheses:\n\n    function(arg, one: if(expr, do: :this, else: :that))\n    function(arg, one: nested_call(a, b, c))\n\nAmbiguity found at:"

  defp fix(source, message, line \\ 1) do
    FixRaiseInKeywordValue.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes bare raise in do: keyword value" do
    input = """
    defmodule M do
      def f(_, _), do: raise ArgumentError, "bad argument"
    end
    """

    expected = """
    defmodule M do
      def f(_, _), do: raise(ArgumentError, "bad argument")
    end
    """

    confirm_fix(fix(input, @diagnostic_msg, 2), expected)
  end

  test "leaves already-parenthesised raise unchanged" do
    input = """
    defmodule M do
      def f(_, _), do: raise(ArgumentError, "bad argument")
    end
    """

    confirm_fix(fix(input, @diagnostic_msg, 2), input)
  end

  test "leaves raise in do...end block unchanged" do
    input = """
    defmodule M do
      def f(_) do
        raise ArgumentError, "bad argument"
      end
    end
    """

    confirm_fix(fix(input, @diagnostic_msg, 2), input)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule M do
      def f(_, _), do: raise ArgumentError, "bad argument"
    end
    """

    assert valid_syntax?(fix(input, @diagnostic_msg, 2))
  end
end
