defmodule Credence.Semantic.FixMapFetchNoneClauseFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixMapFetchNoneClause

  @message """
  the following clause will never match:

      :none ->

  because it attempts to match on the result of:

      Map.fetch(map, key)

  which has type:

      dynamic(:error or {:ok, term()})
  """

  defp fix(source) do
    FixMapFetchNoneClause.fix(source, %{severity: :warning, message: @message, position: 4})
  end

  test "renames :none to :error in a Map.fetch case" do
    input = ~S"""
    defmodule Example do
      def find(map, key) do
        case Map.fetch(map, key) do
          :none -> {:error, :not_found}
          {:ok, value} -> {:ok, value}
        end
      end
    end
    """

    expected = ~S"""
    defmodule Example do
      def find(map, key) do
        case Map.fetch(map, key) do
          :error -> {:error, :not_found}
          {:ok, value} -> {:ok, value}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "renames a bare :none clause with an empty body" do
    input = ~S"""
    defmodule Example do
      def find(map, key) do
        case Map.fetch(map, key) do
          {:ok, v} -> v
          :none ->
        end
      end
    end
    """

    expected = ~S"""
    defmodule Example do
      def find(map, key) do
        case Map.fetch(map, key) do
          {:ok, v} ->
            v

          :error ->
            nil
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "renames when the success clause is guarded" do
    input = ~S"""
    defmodule Example do
      def find(map, key) do
        case Map.fetch(map, key) do
          :none -> :missing
          {:ok, v} when is_integer(v) -> v
        end
      end
    end
    """

    expected = ~S"""
    defmodule Example do
      def find(map, key) do
        case Map.fetch(map, key) do
          :error -> :missing
          {:ok, v} when is_integer(v) -> v
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule Example do
      def find(map, key) do
        case Map.fetch(map, key) do
          :none -> {:error, :not_found}
          {:ok, value} -> {:ok, value}
        end
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "no issue: an :error clause already exists (rename would shadow it)" do
    input = ~S"""
    defmodule Example do
      def find(map, key) do
        case Map.fetch(map, key) do
          :none -> :a
          :error -> :b
          {:ok, v} -> v
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no issue: a catch-all clause handles :error today" do
    input = ~S"""
    defmodule Example do
      def find(map, key) do
        case Map.fetch(map, key) do
          :none -> :a
          {:ok, v} -> v
          _ -> :other
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no issue: a variable fallback clause handles :error today" do
    input = ~S"""
    defmodule Example do
      def find(map, key) do
        case Map.fetch(map, key) do
          :none -> :a
          {:ok, v} -> v
          other -> other
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no issue: guarded :none clause" do
    input = ~S"""
    defmodule Example do
      def find(map, key, flag) do
        case Map.fetch(map, key) do
          :none when flag -> :a
          {:ok, v} -> v
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no issue: duplicated :none clauses" do
    input = ~S"""
    defmodule Example do
      def find(map, key) do
        case Map.fetch(map, key) do
          :none -> :a
          :none -> :b
          {:ok, v} -> v
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no issue: subject is not Map.fetch" do
    input = ~S"""
    defmodule Example do
      def find(map, key) do
        case Map.get(map, key) do
          :none -> {:error, :not_found}
          {:ok, value} -> {:ok, value}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no issue: :none in a case over a plain value" do
    input = ~S"""
    defmodule Example do
      def classify(status) do
        case status do
          :none -> :empty
          :some -> :present
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no issue: piped Map.fetch subject" do
    input = ~S"""
    defmodule Example do
      def find(map, key) do
        case map |> Map.fetch(key) do
          :none -> {:error, :not_found}
          {:ok, value} -> {:ok, value}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "end-to-end: the semantic phase repairs the hallucination" do
    input = ~S"""
    defmodule CredenceNoneClauseE2eFix do
      def find(map, key) do
        case Map.fetch(map, key) do
          :none -> {:error, :not_found}
          {:ok, value} -> {:ok, value}
        end
      end
    end
    """

    expected = ~S"""
    defmodule CredenceNoneClauseE2eFix do
      def find(map, key) do
        case Map.fetch(map, key) do
          :error -> {:error, :not_found}
          {:ok, value} -> {:ok, value}
        end
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: repairs two broken cases in one module" do
    input = ~S"""
    defmodule CredenceNoneClauseE2eTwo do
      def find(map, key) do
        case Map.fetch(map, key) do
          :none -> :missing
          {:ok, value} -> value
        end
      end

      def lookup(map, key) do
        case Map.fetch(map, key) do
          :none -> {:error, :not_found}
          {:ok, value} -> {:ok, value}
        end
      end
    end
    """

    expected = ~S"""
    defmodule CredenceNoneClauseE2eTwo do
      def find(map, key) do
        case Map.fetch(map, key) do
          :error -> :missing
          {:ok, value} -> value
        end
      end

      def lookup(map, key) do
        case Map.fetch(map, key) do
          :error -> {:error, :not_found}
          {:ok, value} -> {:ok, value}
        end
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end
end
