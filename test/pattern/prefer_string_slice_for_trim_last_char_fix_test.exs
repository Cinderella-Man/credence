defmodule Credence.Pattern.PreferStringSliceForTrimLastCharFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferStringSliceForTrimLastChar

  test "rewrites the anti-pattern" do
    input = """
    defmodule Example do
      def trim_last_char(str) when is_binary(str) do
        case String.graphemes(str) do
          [] -> ""
          [_last] -> ""
          [_head | _tail] -> String.slice(str, 0, String.length(str) - 1)
        end
      end
    end
    """

    expected = """
    defmodule Example do
      def trim_last_char(str) when is_binary(str) do
        String.slice(str, 0..-2//1)
      end
    end
    """

    confirm_fix(fix(PreferStringSliceForTrimLastChar, input), expected)
  end

  test "rewrites inside a larger function" do
    input = """
    defmodule Example do
      def process(str) when is_binary(str) do
        trimmed =
          case String.graphemes(str) do
            [] -> ""
            [_last] -> ""
            [_head | _tail] -> String.slice(str, 0, String.length(str) - 1)
          end

        String.upcase(trimmed)
      end
    end
    """

    expected = """
    defmodule Example do
      def process(str) when is_binary(str) do
        trimmed =
          String.slice(str, 0..-2//1)

        String.upcase(trimmed)
      end
    end
    """

    confirm_fix(fix(PreferStringSliceForTrimLastChar, input), expected)
  end

  test "does not modify code already using String.slice" do
    code = """
    defmodule Example do
      def trim_last_char(str) when is_binary(str) do
        String.slice(str, 0..-2//1)
      end
    end
    """

    confirm_fix(fix(PreferStringSliceForTrimLastChar, code), code)
  end
end
