defmodule Credence.Pattern.PreferSigilCharlistFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferSigilCharlist

  test "rewrites a list of single-quoted charlists" do
    input = """
    defmodule M do
      def f, do: ['1', 'abc']
    end
    """

    expected = """
    defmodule M do
      def f, do: [~c"1", ~c"abc"]
    end
    """

    confirm_fix(fix(PreferSigilCharlist, input), expected)
  end

  test "escapes a double quote in the content" do
    input = """
    defmodule M do
      def f, do: 'say "hi"'
    end
    """

    expected = """
    defmodule M do
      def f, do: ~c"say \\"hi\\""
    end
    """

    confirm_fix(fix(PreferSigilCharlist, input), expected)
  end

  test "leaves an existing sigil and a double-quoted apostrophe untouched" do
    input = """
    defmodule M do
      def f, do: {~c"keep", "don't"}
    end
    """

    confirm_fix(fix(PreferSigilCharlist, input), input)
  end
end
