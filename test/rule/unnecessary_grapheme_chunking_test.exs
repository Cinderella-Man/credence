defmodule Credence.Rule.UnnecessaryGraphemeChunkingTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.UnnecessaryGraphemeChunking.check(ast, [])
  end

  describe "UnnecessaryGraphemeChunking" do
    test "passes simple non-string-processing code" do
      code = """
      defmodule GoodMath do
        def add(a, b), do: a + b
      end
      """

      assert check(code) == []
    end

    test "detects grapheme + chunk + join pipeline" do
      code = """
      defmodule BadSubstring do
        def substrings(string, n) do
          string
          |> String.graphemes()
          |> Enum.chunk_every(n, 1, :discard)
          |> Enum.map(&Enum.join/1)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1

      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :unnecessary_grapheme_chunking

      assert issue.message =~ "allocation chain"
      assert issue.message =~ "List of graphemes"
      assert issue.message =~ "Reconstructed binaries"
    end

    test "detects codepoints variant too" do
      code = """
      defmodule BadCodepoints do
        def split(string, n) do
          string
          |> String.codepoints()
          |> Enum.chunk_every(n, 1, :discard)
          |> Enum.map(&Enum.join/1)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
    end

    test "detects multiple pipelines in same module" do
      code = """
      defmodule MultipleBad do
        def a(s), do: s |> String.graphemes() |> Enum.chunk_every(2,1,:discard) |> Enum.map(&Enum.join/1)
        def b(s), do: s |> String.codepoints() |> Enum.chunk_every(2,1,:discard) |> Enum.map(&Enum.join/1)
      end
      """

      issues = check(code)

      assert length(issues) == 2
    end

    test "ignores String.graphemes without chunking" do
      code = """
      defmodule Acceptable do
        def chars(s), do: String.graphemes(s)
      end
      """

      assert check(code) == []
    end

    test "ignores chunking without string expansion" do
      code = """
      defmodule SafeChunking do
        def list_chunks(list) do
          Enum.chunk_every(list, 2)
        end
      end
      """

      assert check(code) == []
    end
  end
end
