defmodule Credence.Pattern.PreferRegexMatchFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferRegexMatch

  describe "rewrites case Regex.run/2 to if Regex.match?/2" do
    test "[_ | _] then catch-all" do
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

      expected = """
      defmodule M do
        def match?(s) do
          if Regex.match?(~r/ab{3,}/, s) do
            "Found a match!"
          else
            "Not matched!"
          end
        end
      end
      """

      confirm_fix(fix(PreferRegexMatch, code), expected)
    end

    test "[_ | _] then nil" do
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

      expected = """
      defmodule M do
        def match?(s) do
          if Regex.match?(~r/\\d+/, s) do
            :found
          else
            :not_found
          end
        end
      end
      """

      confirm_fix(fix(PreferRegexMatch, code), expected)
    end

    test "nil then [_ | _] (bodies map by pattern, not source order)" do
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

      expected = """
      defmodule M do
        def match?(s) do
          if Regex.match?(~r/[a-z]+/, s) do
            :yes
          else
            :no
          end
        end
      end
      """

      confirm_fix(fix(PreferRegexMatch, code), expected)
    end

    test "multi-statement branch bodies" do
      code = """
      defmodule M do
        def match?(s) do
          case Regex.run(~r/\\d+/, s) do
            [_ | _] ->
              log(:hit)
              :yes

            nil ->
              log(:miss)
              :no
          end
        end
      end
      """

      expected = """
      defmodule M do
        def match?(s) do
          if Regex.match?(~r/\\d+/, s) do
            log(:hit)
            :yes
          else
            log(:miss)
            :no
          end
        end
      end
      """

      confirm_fix(fix(PreferRegexMatch, code), expected)
    end
  end

  describe "leaves dropped/unrelated cases untouched" do
    test "Regex.run/3 with options is untouched" do
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

      confirm_fix(fix(PreferRegexMatch, code), code)
    end

    test "bound head is untouched" do
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

      confirm_fix(fix(PreferRegexMatch, code), code)
    end

    test "leading catch-all shadowing [_ | _] is untouched" do
      code = """
      defmodule M do
        def match?(s) do
          case Regex.run(~r/\\d+/, s) do
            _ -> :no
            [_ | _] -> :yes
          end
        end
      end
      """

      confirm_fix(fix(PreferRegexMatch, code), code)
    end

    test "single [_ | _] clause is untouched" do
      code = """
      defmodule M do
        def match?(s) do
          case Regex.run(~r/\\d+/, s) do
            [_ | _] -> :yes
          end
        end
      end
      """

      confirm_fix(fix(PreferRegexMatch, code), code)
    end

    test "bound captures are untouched" do
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

      confirm_fix(fix(PreferRegexMatch, code), code)
    end

    test "named catch-all is untouched" do
      code = """
      defmodule M do
        def match?(s) do
          case Regex.run(~r/\\d+/, s) do
            [_ | _] -> :yes
            other -> other
          end
        end
      end
      """

      confirm_fix(fix(PreferRegexMatch, code), code)
    end

    test "Regex.match? is untouched" do
      code = """
      defmodule M do
        def match?(s), do: Regex.match?(~r/ab{3,}/, s)
      end
      """

      confirm_fix(fix(PreferRegexMatch, code), code)
    end
  end
end
