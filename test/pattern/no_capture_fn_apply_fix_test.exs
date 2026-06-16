defmodule Credence.Pattern.NoCaptureFnApplyFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoCaptureFnApply

  test "inlines a capture applied to a variable" do
    code = """
    defmodule Bad do
      def column_sum(matrix, col) do
        Enum.reduce(matrix, 0, fn el, acc -> acc + (&Enum.at(&1, col)).(el) end)
      end
    end
    """

    expected = """
    defmodule Bad do
      def column_sum(matrix, col) do
        Enum.reduce(matrix, 0, fn el, acc -> acc + Enum.at(el, col) end)
      end
    end
    """

    confirm_fix(fix(NoCaptureFnApply, code), expected)
  end

  test "inlines a capture with arithmetic" do
    code = """
    defmodule Bad do
      def double(x) do
        (& &1 * 2).(x)
      end
    end
    """

    expected = """
    defmodule Bad do
      def double(x) do
        x * 2
      end
    end
    """

    confirm_fix(fix(NoCaptureFnApply, code), expected)
  end

  test "inlines multiple capture applications on separate lines" do
    code = """
    defmodule Bad do
      def process(a, b) do
        x = (& &1 + 1).(a)
        y = (& &1 * 2).(b)
        x + y
      end
    end
    """

    expected = """
    defmodule Bad do
      def process(a, b) do
        x = a + 1
        y = b * 2
        x + y
      end
    end
    """

    confirm_fix(fix(NoCaptureFnApply, code), expected)
  end

  test "leaves a capture with a side-effecting arg untouched" do
    code = """
    defmodule Bad do
      def run do
        (& &1 + &1).(f())
      end
    end
    """

    confirm_fix(fix(NoCaptureFnApply, code), code)
  end

  test "leaves a plain anonymous-function application untouched" do
    code = """
    defmodule Good do
      def process(x) do
        fun = fn y -> y * 2 end
        fun.(x)
      end
    end
    """

    confirm_fix(fix(NoCaptureFnApply, code), code)
  end
end
