defmodule Credence.Pattern.UnnecessaryGraphemeChunkingCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.UnnecessaryGraphemeChunking

  describe "check — positive cases" do
    test "flags graphemes + chunk_every(n, 1, :discard) + &Enum.join/1" do
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

      issues = check(UnnecessaryGraphemeChunking, code)
      assert length(issues) == 1
      assert hd(issues).rule == :unnecessary_grapheme_chunking
    end

    test "flags with fn chunk -> Enum.join(chunk) end" do
      code = """
      defmodule Example do
        def ngrams(string, n) do
          string
          |> String.graphemes()
          |> Enum.chunk_every(n, 1, :discard)
          |> Enum.map(fn chunk -> Enum.join(chunk) end)
        end
      end
      """

      assert length(check(UnnecessaryGraphemeChunking, code)) == 1
    end

    test "flags with fn x -> Enum.join(x, \"\") end" do
      code = """
      defmodule Example do
        def ngrams(string, n) do
          string
          |> String.graphemes()
          |> Enum.chunk_every(n, 1, :discard)
          |> Enum.map(fn x -> Enum.join(x, "") end)
        end
      end
      """

      assert length(check(UnnecessaryGraphemeChunking, code)) == 1
    end

    test "flags with &Enum.join(&1) capture syntax" do
      code = """
      defmodule Example do
        def ngrams(string, n) do
          string
          |> String.graphemes()
          |> Enum.chunk_every(n, 1, :discard)
          |> Enum.map(&Enum.join(&1))
        end
      end
      """

      assert length(check(UnnecessaryGraphemeChunking, code)) == 1
    end

    test "flags with implicit discard (no leftover arg)" do
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

      assert length(check(UnnecessaryGraphemeChunking, code)) == 1
    end

    test "flags with literal chunk size" do
      code = """
      defmodule Example do
        def trigrams(string) do
          string
          |> String.graphemes()
          |> Enum.chunk_every(3, 1, :discard)
          |> Enum.map(&Enum.join/1)
        end
      end
      """

      assert length(check(UnnecessaryGraphemeChunking, code)) == 1
    end

    test "flags with longer pipeline before graphemes" do
      code = """
      defmodule Example do
        def ngrams(string, n) do
          string
          |> String.trim()
          |> String.downcase()
          |> String.graphemes()
          |> Enum.chunk_every(n, 1, :discard)
          |> Enum.map(&Enum.join/1)
        end
      end
      """

      assert length(check(UnnecessaryGraphemeChunking, code)) == 1
    end

    test "flags inside nested anonymous function" do
      code = """
      defmodule Example do
        def all_ngrams(list, n) do
          Enum.map(list, fn s ->
            s
            |> String.graphemes()
            |> Enum.chunk_every(n, 1, :discard)
            |> Enum.map(&Enum.join/1)
          end)
        end
      end
      """

      assert length(check(UnnecessaryGraphemeChunking, code)) == 1
    end

    test "flags one-liner form" do
      code =
        """
        def ngrams(s, n), do: s |> String.graphemes() |> Enum.chunk_every(n, 1, :discard) |> Enum.map(&Enum.join/1)
        """

      assert length(check(UnnecessaryGraphemeChunking, code)) == 1
    end

    test "flags multiple pipelines in same module" do
      code = """
      defmodule Example do
        def bigrams(s),
          do: s |> String.graphemes() |> Enum.chunk_every(2, 1, :discard) |> Enum.map(&Enum.join/1)

        def trigrams(s),
          do: s |> String.graphemes() |> Enum.chunk_every(3, 1, :discard) |> Enum.map(&Enum.join/1)
      end
      """

      assert length(check(UnnecessaryGraphemeChunking, code)) == 2
    end
  end

  describe "check — negative cases" do
    test "does not flag unrelated code" do
      code = """
      defmodule Example do
        def add(a, b), do: a + b
      end
      """

      assert check(UnnecessaryGraphemeChunking, code) == []
    end

    test "does not flag graphemes without chunking" do
      code = """
      defmodule Example do
        def chars(s), do: String.graphemes(s)
      end
      """

      assert check(UnnecessaryGraphemeChunking, code) == []
    end

    test "does not flag chunking without graphemes" do
      code = """
      defmodule Example do
        def chunks(list), do: Enum.chunk_every(list, 2)
      end
      """

      assert check(UnnecessaryGraphemeChunking, code) == []
    end

    test "does not flag String.codepoints variant" do
      code = """
      defmodule Example do
        def ngrams(string, n) do
          string
          |> String.codepoints()
          |> Enum.chunk_every(n, 1, :discard)
          |> Enum.map(&Enum.join/1)
        end
      end
      """

      assert check(UnnecessaryGraphemeChunking, code) == []
    end

    test "does not flag Enum.chunk_by variant" do
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

      assert check(UnnecessaryGraphemeChunking, code) == []
    end

    test "does not flag non-join map" do
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

      assert check(UnnecessaryGraphemeChunking, code) == []
    end

    test "does not flag step != 1" do
      code = """
      defmodule Example do
        def ngrams(string, n) do
          string
          |> String.graphemes()
          |> Enum.chunk_every(n, 2, :discard)
          |> Enum.map(&Enum.join/1)
        end
      end
      """

      assert check(UnnecessaryGraphemeChunking, code) == []
    end

    test "does not flag :trim leftover option" do
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

      assert check(UnnecessaryGraphemeChunking, code) == []
    end

    test "does not flag when intermediate step between chunk and map" do
      code = """
      defmodule Example do
        def process(string, n) do
          string
          |> String.graphemes()
          |> Enum.chunk_every(n, 1, :discard)
          |> Enum.filter(&(length(&1) == n))
          |> Enum.map(&Enum.join/1)
        end
      end
      """

      assert check(UnnecessaryGraphemeChunking, code) == []
    end

    test "does not flag graphemes stored then chunked" do
      code = """
      defmodule Example do
        def ngrams(string, n) do
          g = String.graphemes(string)
          g
          |> Enum.chunk_every(n, 1, :discard)
          |> Enum.map(&Enum.join/1)
        end
      end
      """

      assert check(UnnecessaryGraphemeChunking, code) == []
    end
  end
end
