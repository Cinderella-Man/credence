defmodule Credence.Pattern.UnnecessaryGraphemeChunkingFixTest do
  use ExUnit.Case

  alias Credence.Pattern.UnnecessaryGraphemeChunking

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(UnnecessaryGraphemeChunking, code, [])
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  describe "fix" do
    test "replaces pipeline with for + String.slice comprehension" do
      input = """
      defmodule Example do
        def ngrams(string, n) do
          string
          |> String.graphemes()
          |> Enum.chunk_every(n, 1, :discard)
          |> Enum.map(&Enum.join/1)
        end
      end
      """

      expected = """
      defmodule Example do
        def ngrams(string, n) do
          for i <- 0..(String.length(string) - n)//1 do
            String.slice(string, i, n)
          end
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes pipeline with literal chunk size" do
      input = """
      defmodule Example do
        def trigrams(string) do
          string
          |> String.graphemes()
          |> Enum.chunk_every(3, 1, :discard)
          |> Enum.map(&Enum.join/1)
        end
      end
      """

      expected = """
      defmodule Example do
        def trigrams(string) do
          for i <- 0..(String.length(string) - 3)//1 do
            String.slice(string, i, 3)
          end
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes pipeline with fn join" do
      input = """
      defmodule Example do
        def ngrams(string, n) do
          string
          |> String.graphemes()
          |> Enum.chunk_every(n, 1, :discard)
          |> Enum.map(fn chunk -> Enum.join(chunk) end)
        end
      end
      """

      expected = """
      defmodule Example do
        def ngrams(string, n) do
          for i <- 0..(String.length(string) - n)//1 do
            String.slice(string, i, n)
          end
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes pipeline with implicit discard" do
      input = """
      defmodule Example do
        def ngrams(string, n) do
          string
          |> String.graphemes()
          |> Enum.chunk_every(n, 1)
          |> Enum.map(&Enum.join/1)
        end
      end
      """

      expected = """
      defmodule Example do
        def ngrams(string, n) do
          for i <- 0..(String.length(string) - n)//1 do
            String.slice(string, i, n)
          end
        end
      end
      """

      assert fix(input) == expected
    end

    test "preserves pipeline stages before graphemes" do
      input = """
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

      expected = """
      defmodule Example do
        def ngrams(string, n) do
          for i <-
                0..(String.length(
                      string
                      |> String.trim()
                      |> String.downcase()
                    ) - n)//1 do
            String.slice(
              string
              |> String.trim()
              |> String.downcase(),
              i,
              n
            )
          end
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes multiple pipelines in the same module" do
      input = """
      defmodule Example do
        def bigrams(s),
          do: s |> String.graphemes() |> Enum.chunk_every(2, 1, :discard) |> Enum.map(&Enum.join/1)

        def trigrams(s),
          do: s |> String.graphemes() |> Enum.chunk_every(3, 1, :discard) |> Enum.map(&Enum.join/1)
      end
      """

      expected = """
      defmodule Example do
        def bigrams(s),
          do: for(i <- 0..(String.length(s) - 2)//1) do
          String.slice(s, i, 2)
        end

        def trigrams(s),
          do: for(i <- 0..(String.length(s) - 3)//1) do
          String.slice(s, i, 3)
        end
      end
      """

      assert fix(input) == expected
    end

    test "does not modify code without the pattern" do
      code = """
      defmodule Example do
        def add(a, b), do: a + b
      end
      """

      assert fix(code) == code
    end

    test "fix inside nested anonymous function" do
      input = """
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

      expected = """
      defmodule Example do
        def all_ngrams(list, n) do
          Enum.map(list, fn s ->
            for i <- 0..(String.length(s) - n)//1 do
              String.slice(s, i, n)
            end
          end)
        end
      end
      """

      assert fix(input) == expected
    end
  end
end
