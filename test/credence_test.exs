defmodule CredenceTest do
  use ExUnit.Case

  test "does NOT flag idiomatic word counting" do
    code = """
      defmodule WordCounter do
        def count(text) when is_binary(text) do
          text
          |> String.downcase()
          |> String.replace(~r/[^\p{L}\s]/u, "")
          |> String.split()
          |> Enum.frequencies()
        end
      end
    """

    result = Credence.analyze(code)
    assert result.valid == true
    assert result.issues == []
  end

  test "does NOT flag idiomatic chart counting" do
    code = """
      defmodule CharCounter do
        def count(text) when is_binary(text) do
          text
          |> String.graphemes()
          |> Enum.frequencies()
        end
      end
    """

    result = Credence.analyze(code)
    assert result.valid == true
    assert result.issues == []
  end

  test "does NOT flag idiomatic unique word extraction" do
    code = """
      defmodule UniqueWords do
        def extract(text) when is_binary(text) do
          text
          |> String.downcase()
          |> String.split(~r/\W+/u, trim: true)
          |> MapSet.new()
        end
      end
    """

    result = Credence.analyze(code)
    assert result.valid == true
    assert result.issues == []
  end

  test "does NOT flag idiomatic longest word extraction" do
    code = """
      defmodule LongestWord do
        def find(text) when is_binary(text) do
          text
          |> String.split(~r/\W+/u, trim: true)
          |> Enum.max_by(&String.length/1, fn -> "" end)
        end
      end
    """

    result = Credence.analyze(code)
    assert result.valid == true
    assert result.issues == []
  end

  test "does NOT flag idiomatic word grouping by length" do
    code = """
      defmodule WordGrouper do
        def group_by_length(text) when is_binary(text) do
          text
          |> String.split(~r/\W+/u, trim: true)
          |> Enum.group_by(&String.length/1)
        end
      end
    """

    result = Credence.analyze(code)
    assert result.valid == true
    assert result.issues == []
  end

  test "does NOT flag idiomatic recursive word counting" do
    code = """
      defmodule RecursiveCounter do
        def count(text) when is_binary(text) do
          text
          |> String.downcase()
          |> String.split(~r/\W+/u, trim: true)
          |> do_count(%{})
        end

        defp do_count([], acc), do: acc

        defp do_count([word | rest], acc) do
          updated =
            Map.update(acc, word, 1, fn count -> count + 1 end)

          do_count(rest, updated)
        end
      end
    """

    result = Credence.analyze(code)
    assert result.valid == true
    assert result.issues == []
  end

  test "does NOT flag idiomatic index by first letter" do
    code = """
      defmodule IndexByFirstLetter do
        def build(words) do
          Enum.reduce(words, %{}, fn word, acc ->
            first = String.first(word)

            Map.update(acc, first, [word], fn existing ->
              [word | existing]
            end)
          end)
        end
      end
    """

    result = Credence.analyze(code)
    assert result.valid == true
    assert result.issues == []
  end
end
