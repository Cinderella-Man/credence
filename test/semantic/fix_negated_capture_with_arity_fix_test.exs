defmodule Credence.Semantic.FixNegatedCaptureWithArityFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixNegatedCaptureWithArity

  # Real message shape from Code.with_diagnostics (abbreviated body; the rule
  # matches on the "invalid args for &" prefix plus the negated `Got:` line).
  @real_message "invalid args for &, expected one of: ...\n\nGot: !Enum.empty?() / 1"

  defp fix(source, line \\ 1) do
    FixNegatedCaptureWithArity.fix(source, %{
      severity: :error,
      message: @real_message,
      position: {line, 1}
    })
  end

  test "fixes remote &(!Mod.fun/1) to &(!Mod.fun(&1))" do
    input = """
    defmodule Example do
      def any_full?(lists) do
        Enum.any?(lists, &(!Enum.empty?/1))
      end
    end
    """

    expected = """
    defmodule Example do
      def any_full?(lists) do
        Enum.any?(lists, &(!Enum.empty?(&1)))
      end
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "fixes remote &(not Mod.fun/1) to &(not Mod.fun(&1))" do
    input = """
    defmodule Example do
      def any_full?(lists) do
        Enum.any?(lists, &(not Enum.empty?/1))
      end
    end
    """

    expected = """
    defmodule Example do
      def any_full?(lists) do
        Enum.any?(lists, &(not Enum.empty?(&1)))
      end
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "fixes local &(!fun/1) to &(!fun(&1))" do
    input = """
    defmodule Example do
      def not_blank(strings) do
        Enum.filter(strings, &(!blank?/1))
      end

      defp blank?(s), do: s == ""
    end
    """

    expected = """
    defmodule Example do
      def not_blank(strings) do
        Enum.filter(strings, &(!blank?(&1)))
      end

      defp blank?(s), do: s == ""
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "fixes local capture written with empty call parens &(!fun()/1)" do
    input = """
    defmodule Example do
      def not_blank(strings) do
        Enum.filter(strings, &(!blank?()/1))
      end

      defp blank?(s), do: s == ""
    end
    """

    expected = """
    defmodule Example do
      def not_blank(strings) do
        Enum.filter(strings, &(!blank?(&1)))
      end

      defp blank?(s), do: s == ""
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "builds one placeholder per declared arity: &(!Mod.fun/2)" do
    input = """
    defmodule Example do
      def missing?(haystacks, needle) do
        Enum.reject(haystacks, &(!String.contains?/2)).(needle)
      end
    end
    """

    expected = """
    defmodule Example do
      def missing?(haystacks, needle) do
        Enum.reject(haystacks, &(!String.contains?(&1, &2))).(needle)
      end
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "leaves /0 arities unchanged (a capture must take at least one argument)" do
    input = """
    defmodule Example do
      def check do
        Enum.map([1], &(!zero_arity_fun/0))
      end
    end
    """

    confirm_fix(fix(input, 3), input)
  end

  test "leaves valid captures and divisions unchanged" do
    input = """
    defmodule Example do
      def go(lists) do
        a = Enum.any?(lists, &(!Enum.empty?(&1)))
        b = Enum.map(lists, &Enum.count/1)
        c = Enum.map([2, 4], &(&1 / 2))
        d = Enum.map([true], &(!&1 / 2))
        {a, b, c, d}
      end
    end
    """

    confirm_fix(fix(input, 3), input)
  end

  test "leaves unparseable source unchanged" do
    input = "def broken do"
    confirm_fix(fix(input), input)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def any_full?(lists) do
        Enum.any?(lists, &(!Enum.empty?/1))
      end
    end
    """

    assert valid_syntax?(fix(input, 3))
  end
end
