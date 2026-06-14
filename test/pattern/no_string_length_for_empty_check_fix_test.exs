defmodule Credence.Pattern.NoStringLengthForEmptyCheckFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoStringLengthForEmptyCheck

  test "String.length(String.trim(line)) == 0 → String.trim(line) == \"\"" do
    input = """
    defmodule M do
      def f(line), do: String.length(String.trim(line)) == 0
    end
    """

    expected = """
    defmodule M do
      def f(line), do: String.trim(line) == ""
    end
    """

    confirm_fix(fix(NoStringLengthForEmptyCheck, input), expected)
  end

  test "flipped order and != become s != \"\"" do
    input = """
    defmodule M do
      def f(x), do: 0 != String.length(String.downcase(x))
    end
    """

    expected = """
    defmodule M do
      def f(x), do: String.downcase(x) != ""
    end
    """

    confirm_fix(fix(NoStringLengthForEmptyCheck, input), expected)
  end

  test "leaves a bare-variable argument unchanged" do
    input = """
    defmodule M do
      def f(s), do: String.length(s) == 0
    end
    """

    confirm_fix(fix(NoStringLengthForEmptyCheck, input), input)
  end
end
