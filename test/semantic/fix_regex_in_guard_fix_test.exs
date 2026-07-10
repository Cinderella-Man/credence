defmodule Credence.Semantic.FixRegexInGuardFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixRegexInGuard

  @real_message "escaped Regex structs are not allowed in match or guards"

  defp fix(source, message \\ @real_message, line \\ 2) do
    FixRegexInGuard.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  test "rewrites multi-clause regex guards into chained helpers" do
    input = """
    defmodule Demo do
      def classify(str) when is_binary(str) and str =~ ~r/^\\s*$/ do
        :blank
      end
      def classify(str) when is_binary(str) and str =~ ~r/^http/ do
        :url
      end
      def classify(_), do: :other
    end
    """

    expected = """
    defmodule Demo do
      def classify(str) when is_binary(str) do
        if Regex.match?(~r/^\\s*$/, str),
          do: :blank,
          else: classify_0(str)
      end

      defp classify_0(str) do
        if Regex.match?(~r/^http/, str),
          do: :url,
          else: :other
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "rewrites single clause with regex guard" do
    input = """
    defmodule Demo do
      def blank?(str) when is_binary(str) and str =~ ~r/^\\s*$/ do
        true
      end
    end
    """

    expected = """
    defmodule Demo do
      def blank?(str) when is_binary(str) do
        if Regex.match?(~r/^\\s*$/, str),
          do: true,
          else: nil
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Demo do
      def classify(str) when is_binary(str) and str =~ ~r/^\\s*$/ do
        :blank
      end
      def classify(str) when is_binary(str) and str =~ ~r/^http/ do
        :url
      end
      def classify(_), do: :other
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "returns source unchanged when no regex in guard" do
    input = """
    defmodule Demo do
      def classify(str) when is_binary(str), do: :ok
      def classify(_), do: :error
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not touch code without when guards" do
    input = """
    defmodule Demo do
      def classify(str), do: :ok
    end
    """

    confirm_fix(fix(input), input)
  end
end
