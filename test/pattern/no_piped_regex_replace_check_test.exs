defmodule Credence.Pattern.NoPipedRegexReplaceCheckTest do
  use ExUnit.Case

  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoPipedRegexReplace.check(ast, [])
  end

  describe "flags piped Regex.replace" do
    test "flags simple pipeline" do
      code = """
      defmodule M do
        def clean(s), do: s |> Regex.replace(~r/[^a-z]/, "")
      end
      """

      assert [%Issue{rule: :no_piped_regex_replace}] = check(code)
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

      assert [%Issue{rule: :no_piped_regex_replace}] = check(code)
    end

    test "flags pipeline with options argument" do
      code = """
      defmodule M do
        def clean(s), do: s |> Regex.replace(~r/\\s+/, " ", global: true)
      end
      """

      assert [%Issue{rule: :no_piped_regex_replace}] = check(code)
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

      issues = check(code)
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

      assert check(code) == []
    end

    test "does not flag String.replace in pipeline" do
      code = """
      defmodule M do
        def clean(s), do: s |> String.replace(~r/[^a-z]/, "")
      end
      """

      assert check(code) == []
    end

    test "does not flag Regex.replace inside then/2" do
      code = """
      defmodule M do
        def clean(s) do
          s |> then(fn x -> Regex.replace(~r/[^a-z]/, x, "") end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag unrelated pipe" do
      code = """
      defmodule M do
        def clean(s), do: s |> String.downcase() |> String.trim()
      end
      """

      assert check(code) == []
    end
  end
end
