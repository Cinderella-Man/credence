defmodule Credence.Pattern.NoPipedRegexReplaceCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoPipedRegexReplace

  describe "flags piped Regex.replace" do
    test "flags simple pipeline" do
      code = """
      defmodule M do
        def clean(s), do: s |> Regex.replace(~r/[^a-z]/, "")
      end
      """

      assert [%Issue{rule: :no_piped_regex_replace}] = check(NoPipedRegexReplace, code)
    end

    test "flags multi-line pipeline" do
      code = """
      defmodule M do
        def clean(s) do
          s
          |> String.downcase()
          |> Regex.replace(~r/[^a-z0-9]/, "")
        end
      end
      """

      assert [%Issue{rule: :no_piped_regex_replace}] = check(NoPipedRegexReplace, code)
    end

    test "flags pipeline with options argument" do
      code = """
      defmodule M do
        def clean(s), do: s |> Regex.replace(~r/\\s+/, " ", global: true)
      end
      """

      assert [%Issue{rule: :no_piped_regex_replace}] = check(NoPipedRegexReplace, code)
    end

    test "flags multiple piped Regex.replace calls" do
      code = """
      defmodule M do
        def clean(s) do
          s
          |> Regex.replace(~r/[^a-z]/, "")
          |> Regex.replace(~r/\\s+/, " ")
        end
      end
      """

      issues = check(NoPipedRegexReplace, code)
      assert length(issues) == 2
    end
  end

  describe "does NOT flag correct usage" do
    test "does not flag non-piped Regex.replace" do
      code = """
      defmodule M do
        def clean(s), do: Regex.replace(~r/[^a-z]/, s, "")
      end
      """

      assert check(NoPipedRegexReplace, code) == []
    end

    test "does not flag String.replace in pipeline" do
      code = """
      defmodule M do
        def clean(s), do: s |> String.replace(~r/[^a-z]/, "")
      end
      """

      assert check(NoPipedRegexReplace, code) == []
    end

    test "does not flag Regex.replace inside then/2" do
      code = """
      defmodule M do
        def clean(s) do
          s |> then(fn x -> Regex.replace(~r/[^a-z]/, x, "") end)
        end
      end
      """

      assert check(NoPipedRegexReplace, code) == []
    end

    test "does not flag unrelated pipe" do
      code = """
      defmodule M do
        def clean(s), do: s |> String.downcase() |> String.trim()
      end
      """

      assert check(NoPipedRegexReplace, code) == []
    end

    # `regex |> Regex.replace(string, repl)` is the CORRECT (regex, string, repl)
    # form — the piped value is the regex, the explicit first arg is the string.
    # Rewriting to String.replace would put a %Regex{} in the subject slot and
    # crash, so these must not be flagged.
    test "does not flag a ~r-sigil piped into Regex.replace (correct usage)" do
      code = "~r/[a-z]/ |> Regex.replace(input, fn x -> x end)"

      assert check(NoPipedRegexReplace, code) == []
    end

    test "does not flag a Regex.compile! result piped into Regex.replace" do
      code = ~S'pattern |> Regex.compile!() |> Regex.replace(input, "x")'

      assert check(NoPipedRegexReplace, code) == []
    end

    test "does not flag a regex variable piped into Regex.replace" do
      code = ~S're |> Regex.replace(subject, "x")'

      assert check(NoPipedRegexReplace, code) == []
    end
  end
end
