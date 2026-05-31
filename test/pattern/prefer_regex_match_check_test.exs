defmodule Credence.Pattern.PreferRegexMatchCheckTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.PreferRegexMatch

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    PreferRegexMatch.check(ast, [])
  end

  describe "flags Regex.run used as boolean match check" do
    test "flags case Regex.run with [_ | _] and catch-all" do
      code = """
      defmodule M do
        def match?(s) do
          case Regex.run(~r/ab{3,}/, s) do
            [_ | _] -> "Found a match!"
            _ -> "Not matched!"
          end
        end
      end
      """

      assert [%Issue{rule: :prefer_regex_match}] = check(code)
    end

    test "flags case Regex.run with [_ | _] and nil" do
      code = """
      defmodule M do
        def match?(s) do
          case Regex.run(~r/\\d+/, s) do
            [_ | _] -> :found
            nil -> :not_found
          end
        end
      end
      """

      assert [%Issue{rule: :prefer_regex_match}] = check(code)
    end

    test "flags case Regex.run with reversed clause order" do
      code = """
      defmodule M do
        def match?(s) do
          case Regex.run(~r/[a-z]+/, s) do
            nil -> :no
            [_ | _] -> :yes
          end
        end
      end
      """

      assert [%Issue{rule: :prefer_regex_match}] = check(code)
    end

    test "flags Regex.run with options" do
      code = """
      defmodule M do
        def match?(s) do
          case Regex.run(~r/foo/i, s, capture: :first) do
            [_ | _] -> true
            _ -> false
          end
        end
      end
      """

      assert [%Issue{rule: :prefer_regex_match}] = check(code)
    end
  end

  describe "does NOT flag correct usage" do
    test "does not flag Regex.run when captures are used" do
      code = """
      defmodule M do
        def extract(s) do
          case Regex.run(~r/(\\d+)-(\\d+)/, s) do
            [_, a, b] -> {String.to_integer(a), String.to_integer(b)}
            nil -> nil
          end
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Regex.match?" do
      code = """
      defmodule M do
        def match?(s), do: Regex.match?(~r/ab{3,}/, s)
      end
      """

      assert check(code) == []
    end

    test "does not flag Regex.run in non-case context" do
      code = """
      defmodule M do
        def extract(s), do: Regex.run(~r/\\d+/, s)
      end
      """

      assert check(code) == []
    end

    test "does not flag case Regex.run when head is bound" do
      code = """
      defmodule M do
        def first_match(s) do
          case Regex.run(~r/\\d+/, s) do
            [match | _] -> match
            nil -> nil
          end
        end
      end
      """

      assert check(code) == []
    end
  end
end
