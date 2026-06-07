defmodule Credence.Pattern.PreferRegexMatchCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.PreferRegexMatch

  describe "flags Regex.run/2 used only as a boolean match check" do
    test "flags [_ | _] then catch-all" do
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

      assert [%Issue{rule: :prefer_regex_match}] = check(PreferRegexMatch, code)
    end

    test "flags [_ | _] then nil" do
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

      assert [%Issue{rule: :prefer_regex_match}] = check(PreferRegexMatch, code)
    end

    test "flags nil then [_ | _] (disjoint, either order)" do
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

      assert [%Issue{rule: :prefer_regex_match}] = check(PreferRegexMatch, code)
    end
  end

  describe "does NOT flag — captures are inspected" do
    test "does not flag when captures are bound" do
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

      assert check(PreferRegexMatch, code) == []
    end

    test "does not flag when the head is bound" do
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

      assert check(PreferRegexMatch, code) == []
    end

    test "does not flag a specific-capture list pattern" do
      code = """
      defmodule M do
        def kind(s) do
          case Regex.run(~r/\\w+/, s) do
            ["yes"] -> :y
            _ -> :n
          end
        end
      end
      """

      assert check(PreferRegexMatch, code) == []
    end
  end

  describe "does NOT flag — not the safe shape" do
    test "does not flag Regex.run/3 (options change the matched list)" do
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

      assert check(PreferRegexMatch, code) == []
    end

    test "does not flag a leading catch-all that shadows [_ | _]" do
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

      assert check(PreferRegexMatch, code) == []
    end

    test "does not flag a single [_ | _] clause (no-match would raise)" do
      code = """
      defmodule M do
        def match?(s) do
          case Regex.run(~r/\\d+/, s) do
            [_ | _] -> :yes
          end
        end
      end
      """

      assert check(PreferRegexMatch, code) == []
    end

    test "does not flag a named catch-all (body may read the bound value)" do
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

      assert check(PreferRegexMatch, code) == []
    end

    test "does not flag a guarded [_ | _] clause" do
      code = """
      defmodule M do
        def match?(s, n) do
          case Regex.run(~r/\\d+/, s) do
            [_ | _] when n > 0 -> :yes
            _ -> :no
          end
        end
      end
      """

      assert check(PreferRegexMatch, code) == []
    end

    test "does not flag three clauses" do
      code = """
      defmodule M do
        def match?(s) do
          case Regex.run(~r/\\d+/, s) do
            ["0"] -> :zero
            [_ | _] -> :other
            nil -> :no
          end
        end
      end
      """

      assert check(PreferRegexMatch, code) == []
    end
  end

  describe "does NOT flag — unrelated code" do
    test "does not flag Regex.match?" do
      code = """
      defmodule M do
        def match?(s), do: Regex.match?(~r/ab{3,}/, s)
      end
      """

      assert check(PreferRegexMatch, code) == []
    end

    test "does not flag Regex.run outside a case" do
      code = """
      defmodule M do
        def extract(s), do: Regex.run(~r/\\d+/, s)
      end
      """

      assert check(PreferRegexMatch, code) == []
    end
  end
end
