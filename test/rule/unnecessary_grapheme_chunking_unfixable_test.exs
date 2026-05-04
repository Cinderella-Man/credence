defmodule Credence.Rule.UnnecessaryGraphemeChunking.UnfixableTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.UnnecessaryGraphemeChunking.Unfixable.check(ast, [])
  end

  describe "positive cases — should flag" do
    test "flags codepoints + chunk_every + map(&Enum.join/1)" do
      code = """
      defmodule Example do
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
      assert hd(issues).rule == :unnecessary_grapheme_chunking
    end

    test "flags graphemes + chunk_by + map(&Enum.join/1)" do
      code = """
      defmodule Example do
        def group(string) do
          string
          |> String.graphemes()
          |> Enum.chunk_by(&(&1 == " "))
          |> Enum.map(&Enum.join/1)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags graphemes + chunk_every with step 2 + map(&Enum.join/1)" do
      code = """
      defmodule Example do
        def bigram_skip(string, n) do
          string
          |> String.graphemes()
          |> Enum.chunk_every(n, 2, :discard)
          |> Enum.map(&Enum.join/1)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags graphemes + chunk_every + non-join map" do
      code = """
      defmodule Example do
        def process(string, n) do
          string
          |> String.graphemes()
          |> Enum.chunk_every(n, 1, :discard)
          |> Enum.map(&length/1)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags graphemes + chunk_every with :trim + map(&Enum.join/1)" do
      code = """
      defmodule Example do
        def ngrams(string, n) do
          string
          |> String.graphemes()
          |> Enum.chunk_every(n, 1, :trim)
          |> Enum.map(&Enum.join/1)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags graphemes + chunk_every + map with fn doing something other than join" do
      code = """
      defmodule Example do
        def upcase_chunks(string, n) do
          string
          |> String.graphemes()
          |> Enum.chunk_every(n, 1, :discard)
          |> Enum.map(fn chunk -> chunk |> Enum.join() |> String.upcase() end)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags multiple unfixable pipelines in same module" do
      code = """
      defmodule Example do
        def a(s, n) do
          s
          |> String.codepoints()
          |> Enum.chunk_every(n, 1, :discard)
          |> Enum.map(&Enum.join/1)
        end

        def b(s, n) do
          s
          |> String.graphemes()
          |> Enum.chunk_every(n, 2, :discard)
          |> Enum.map(&Enum.join/1)
        end
      end
      """

      assert length(check(code)) == 2
    end
  end

  describe "negative cases — should not flag" do
    test "does not flag the fixable pattern (handled by sibling module)" do
      code = """
      defmodule Example do
        def ngrams(string, n) do
          string
          |> String.graphemes()
          |> Enum.chunk_every(n, 1, :discard)
          |> Enum.map(&Enum.join/1)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag fixable pattern with implicit discard" do
      code = """
      defmodule Example do
        def ngrams(string, n) do
          string
          |> String.graphemes()
          |> Enum.chunk_every(n, 1)
          |> Enum.map(&Enum.join/1)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag fixable pattern with fn join" do
      code = """
      defmodule Example do
        def ngrams(string, n) do
          string
          |> String.graphemes()
          |> Enum.chunk_every(n, 1, :discard)
          |> Enum.map(fn x -> Enum.join(x) end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag unrelated code" do
      code = """
      defmodule Example do
        def add(a, b), do: a + b
      end
      """

      assert check(code) == []
    end

    test "does not flag graphemes without chunking" do
      code = """
      defmodule Example do
        def chars(s), do: String.graphemes(s)
      end
      """

      assert check(code) == []
    end

    test "does not flag chunking without graphemes" do
      code = """
      defmodule Example do
        def chunks(list), do: Enum.chunk_every(list, 2)
      end
      """

      assert check(code) == []
    end

    test "does not flag map without graphemes + chunk" do
      code = """
      defmodule Example do
        def process(list), do: Enum.map(list, &to_string/1)
      end
      """

      assert check(code) == []
    end
  end
end
