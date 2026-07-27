defmodule Credence.Pattern.FixRegexMatchSwappedArgsFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.FixRegexMatchSwappedArgs

  test "rewrites regex literal on the left of =~" do
    input = """
    defmodule M do
      def f(x), do: ~r/abc/ =~ x
    end
    """

    expected = """
    defmodule M do
      def f(x), do: x =~ ~r/abc/
    end
    """

    confirm_fix(fix(FixRegexMatchSwappedArgs, input), expected)
  end

  test "rewrites module attribute regex on the left of =~" do
    input = """
    defmodule M do
      @re ~r/^[a-z]+$/
      def f(x), do: @re =~ x
    end
    """

    expected = """
    defmodule M do
      @re ~r/^[a-z]+$/
      def f(x), do: x =~ @re
    end
    """

    confirm_fix(fix(FixRegexMatchSwappedArgs, input), expected)
  end
end
