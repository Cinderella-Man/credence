defmodule Credence.Semantic.FixRaiseInKeywordValueFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.RuleHelpers
  alias Credence.Semantic.FixRaiseInKeywordValue

  @diagnostic_msg "missing parentheses for expression following \"do:\" keyword. Parentheses are required to solve ambiguity inside keywords.\n\nThis error happens when you have function calls without parentheses inside keywords. For example:\n\n    function(arg, one: nested_call a, b, c)\n    function(arg, one: if expr, do: :this, else: :that)\n\nIn the examples above, we don't know if the arguments \"b\" and \"c\" apply to the function \"function\" or \"nested_call\". Or if the keywords \"do\" and \"else\" apply to the function \"function\" or \"if\". You can solve this by explicitly adding parentheses:\n\n    function(arg, one: if(expr, do: :this, else: :that))\n    function(arg, one: nested_call(a, b, c))\n\nAmbiguity found at:"

  defp fix(source, message, line) do
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

  test "fixes bare raise with keyword arguments" do
    input = """
    defmodule M do
      def f(_), do: raise ArgumentError, message: "bad"
    end
    """

    expected = """
    defmodule M do
      def f(_), do: raise(ArgumentError, message: "bad")
    end
    """

    confirm_fix(fix(input, @diagnostic_msg, 2), expected)
  end

  test "fixes only the bare raise at the diagnostic position" do
    input = """
    defmodule M do
      def a(_), do: raise ArgumentError, "x"
      def b(_), do: raise "boom"
    end
    """

    expected = """
    defmodule M do
      def a(_), do: raise(ArgumentError, "x")
      def b(_), do: raise "boom"
    end
    """

    confirm_fix(fix(input, @diagnostic_msg, 2), expected)
  end

  test "fixes bare raise inside an if do: value (printer parenthesises the if too)" do
    input = """
    defmodule M do
      def f(x), do: if x, do: raise ArgumentError, "bad"
    end
    """

    expected = """
    defmodule M do
      def f(x), do: if(x, do: raise(ArgumentError, "bad"))
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

  test "leaves a non-raise ambiguity unchanged" do
    input = """
    defmodule M do
      def f(x), do: foo x, bar: 1
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

  test "fix resolves the diagnostic: no matching warning remains" do
    input = """
    defmodule CredenceRaiseInKeywordResolved do
      def f(_, _), do: raise ArgumentError, "bad argument"
    end
    """

    {:ok, before_diags} = RuleHelpers.compile_and_capture(input)
    assert Enum.any?(before_diags, &FixRaiseInKeywordValue.match?/1)

    fixed = fix(input, @diagnostic_msg, 2)
    {:ok, after_diags} = RuleHelpers.compile_and_capture(fixed)
    refute Enum.any?(after_diags, &FixRaiseInKeywordValue.match?/1)
  end

  test "semantic pipeline dispatches the diagnostic to this rule" do
    input = """
    defmodule CredenceRaiseInKeywordPipeline do
      def f(_, _), do: raise ArgumentError, "bad argument"
    end
    """

    expected = """
    defmodule CredenceRaiseInKeywordPipeline do
      def f(_, _), do: raise(ArgumentError, "bad argument")
    end
    """

    {:ok, before_diags} = RuleHelpers.compile_and_capture(input)
    assert Enum.any?(before_diags, &FixRaiseInKeywordValue.match?/1)

    fixed = Credence.Semantic.fix(input)
    confirm_fix(fixed, expected)

    assert {:ok, after_diags} = RuleHelpers.compile_and_capture(fixed)
    refute Enum.any?(after_diags, &FixRaiseInKeywordValue.match?/1)
  end

  test "fixes raise whose argument is a bare if (keywords stay bound to the if)" do
    input = """
    defmodule M do
      def f(x), do: raise if x, do: RuntimeError, else: ArgumentError
    end
    """

    expected = """
    defmodule M do
      def f(x), do: raise(if x, do: RuntimeError, else: ArgumentError)
    end
    """

    confirm_fix(fix(input, @diagnostic_msg, 2), expected)
  end
end
