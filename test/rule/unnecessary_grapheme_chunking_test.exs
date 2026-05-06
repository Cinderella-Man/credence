defmodule Credence.Pattern.UnnecessaryGraphemeChunkingTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.UnnecessaryGraphemeChunking.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.UnnecessaryGraphemeChunking.fix(code, [])
  end

  # Macro.to_string may expand multi-arg calls across multiple lines.
  # Collapse whitespace so substring assertions work regardless of formatting.
  defp norm(str) do
    str
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/\(\s+/, "(")
    |> String.replace(~r/\s+\)/, ")")
  end

  # ===========================================================================
  # check — positive cases (should flag)
  # ===========================================================================

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

      issues = check(code)
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

      assert length(check(code)) == 1
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

      assert length(check(code)) == 1
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

      assert length(check(code)) == 1
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

      assert length(check(code)) == 1
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

      assert length(check(code)) == 1
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

      assert length(check(code)) == 1
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

      assert length(check(code)) == 1
    end

    test "flags one-liner form" do
      code =
        "def ngrams(s, n), do: s |> String.graphemes() |> Enum.chunk_every(n, 1, :discard) |> Enum.map(&Enum.join/1)"

      assert length(check(code)) == 1
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

      assert length(check(code)) == 2
    end
  end

  # ===========================================================================
  # check — negative cases (should NOT flag)
  # ===========================================================================

  describe "check — negative cases" do
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

      assert check(code) == []
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

      assert check(code) == []
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

      assert check(code) == []
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

      assert check(code) == []
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

      assert check(code) == []
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

      assert check(code) == []
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

      assert check(code) == []
    end
  end

  # ===========================================================================
  # fix
  # ===========================================================================

  describe "fix" do
    test "produces valid Elixir code" do
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

      fixed = fix(code)
      assert {:ok, _} = Code.string_to_quoted(fixed)
    end

    test "replaces pipeline with for + String.slice comprehension" do
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

      fixed = fix(code)
      assert {:ok, _} = Code.string_to_quoted(fixed)
      f = norm(fixed)
      assert f =~ "for"
      assert f =~ "String.length"
      assert f =~ "String.slice"
      assert f =~ "0.."
      refute f =~ "String.graphemes"
      refute f =~ "chunk_every"
      refute f =~ "Enum.join"
    end

    test "fixes pipeline with literal chunk size" do
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

      fixed = fix(code)
      assert {:ok, _} = Code.string_to_quoted(fixed)
      f = norm(fixed)
      assert f =~ "String.length(string)"
      assert f =~ "String.slice(string, i, 3)"
      refute f =~ "String.graphemes"
    end

    test "fixes pipeline with fn join" do
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

      fixed = fix(code)
      assert {:ok, _} = Code.string_to_quoted(fixed)
      f = norm(fixed)
      assert f =~ "for"
      assert f =~ "String.slice"
      refute f =~ "String.graphemes"
    end

    test "fixes pipeline with implicit discard" do
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

      fixed = fix(code)
      assert {:ok, _} = Code.string_to_quoted(fixed)
      f = norm(fixed)
      assert f =~ "for"
      assert f =~ "String.slice"
      refute f =~ "String.graphemes"
    end

    test "preserves pipeline stages before graphemes" do
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

      fixed = fix(code)
      assert {:ok, _} = Code.string_to_quoted(fixed)
      f = norm(fixed)
      assert f =~ "String.trim"
      assert f =~ "String.downcase"
      assert f =~ "for"
      assert f =~ "String.length"
      assert f =~ "String.slice"
      refute f =~ "String.graphemes"
    end

    test "fixes multiple pipelines in the same module" do
      code = """
      defmodule Example do
        def bigrams(s),
          do: s |> String.graphemes() |> Enum.chunk_every(2, 1, :discard) |> Enum.map(&Enum.join/1)

        def trigrams(s),
          do: s |> String.graphemes() |> Enum.chunk_every(3, 1, :discard) |> Enum.map(&Enum.join/1)
      end
      """

      fixed = fix(code)
      assert {:ok, _} = Code.string_to_quoted(fixed)
      f = norm(fixed)
      refute f =~ "String.graphemes"
      refute f =~ "chunk_every"
      assert length(Regex.scan(~r/\bfor\b/, f)) == 2
    end

    test "does not modify code without the pattern" do
      code = """
      defmodule Example do
        def add(a, b), do: a + b
      end
      """

      fixed = fix(code)
      refute fixed =~ "String.slice"
    end

    test "fix inside nested anonymous function" do
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

      fixed = fix(code)
      assert {:ok, _} = Code.string_to_quoted(fixed)
      f = norm(fixed)
      assert f =~ "String.slice"
      refute f =~ "String.graphemes"
    end
  end
end
