defmodule Credence.Pattern.NoPipedRegexReplaceFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoPipedRegexReplace

  describe "replaces piped Regex.replace with String.replace" do
    test "simple pipeline" do
      code = """
      defmodule M do
        def clean(s), do: s |> Regex.replace(~r/[^a-z]/, "")
      end
      """

      expected = """
      defmodule M do
        def clean(s), do: s |> String.replace(~r/[^a-z]/, "")
      end
      """

      confirm_fix(fix(NoPipedRegexReplace, code), expected)
    end

    test "multi-line pipeline from log (idx=0 attempt 2)" do
      code = """
      defmodule PalindromeChecker do
        def palindrome?(input_string) when is_binary(input_string) do
          cleaned = input_string
            |> String.downcase()
            |> Regex.replace(~r/[^a-z0-9]/, "")

          cleaned == String.reverse(cleaned)
        end
      end
      """

      expected = """
      defmodule PalindromeChecker do
        def palindrome?(input_string) when is_binary(input_string) do
          cleaned = input_string
            |> String.downcase()
            |> String.replace(~r/[^a-z0-9]/, "")

          cleaned == String.reverse(cleaned)
        end
      end
      """

      confirm_fix(fix(NoPipedRegexReplace, code), expected)
    end

    test "pipeline with options argument" do
      code = """
      defmodule M do
        def clean(s), do: s |> Regex.replace(~r/\\s+/, " ", global: true)
      end
      """

      expected = """
      defmodule M do
        def clean(s), do: s |> String.replace(~r/\\s+/, " ", global: true)
      end
      """

      confirm_fix(fix(NoPipedRegexReplace, code), expected)
    end

    test "multiple piped Regex.replace calls" do
      code = """
      defmodule M do
        def clean(s) do
          s
          |> Regex.replace(~r/[^a-z]/, "")
          |> Regex.replace(~r/\\s+/, " ")
        end
      end
      """

      expected = """
      defmodule M do
        def clean(s) do
          s
          |> String.replace(~r/[^a-z]/, "")
          |> String.replace(~r/\\s+/, " ")
        end
      end
      """

      confirm_fix(fix(NoPipedRegexReplace, code), expected)
    end
  end

  describe "does not modify correct usage" do
    test "non-piped Regex.replace unchanged" do
      code = """
      defmodule M do
        def clean(s), do: Regex.replace(~r/[^a-z]/, s, "")
      end
      """

      confirm_fix(fix(NoPipedRegexReplace, code), code)
    end

    test "String.replace in pipeline unchanged" do
      code = """
      defmodule M do
        def clean(s), do: s |> String.replace(~r/[^a-z]/, "")
      end
      """

      confirm_fix(fix(NoPipedRegexReplace, code), code)
    end

    test "Regex.replace inside then/2 unchanged" do
      code = """
      defmodule M do
        def clean(s) do
          s |> then(fn x -> Regex.replace(~r/[^a-z]/, x, "") end)
        end
      end
      """

      confirm_fix(fix(NoPipedRegexReplace, code), code)
    end

    test "code with no Regex usage unchanged" do
      code = """
      defmodule M do
        def clean(s), do: s |> String.downcase() |> String.trim()
      end
      """

      confirm_fix(fix(NoPipedRegexReplace, code), code)
    end

    # Correct `regex |> Regex.replace(string, repl)` must be left untouched —
    # rewriting it to String.replace would crash on the %Regex{} subject.
    test "leaves a ~r-sigil piped into Regex.replace unchanged" do
      code = "~r/[a-z]/ |> Regex.replace(input, fn x -> x end)"

      confirm_fix(fix(NoPipedRegexReplace, code), code)
    end

    test "leaves a custom module aliased as Regex unchanged" do
      code = """
      defmodule NoPipedRegexReplaceCustomAliasFixFixture do
        alias MyRegex, as: Regex

        def clean(value, replacement), do: value |> Regex.replace(~r/x/, replacement)
      end
      """

      confirm_fix(fix(NoPipedRegexReplace, code), code)
    end
  end
end
