defmodule Credence.Semantic.NoCryptoHashPipeSwappedArgsFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoCryptoHashPipeSwappedArgs

  @match_message "** (ArgumentError) errors were found at the given position:\n\n  * 2nd argument: not an iodata term\n\n    (crypto :erlang.crypto.hash/2)"

  defp fix(source, message, line \\ 1) do
    NoCryptoHashPipeSwappedArgs.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes the source" do
    input = """
    defmodule PipeSwappedCryptoHash do
      @moduledoc "Demonstrates piping file contents into :crypto.hash with swapped args."

      def hash_file(path) do
        path
        |> File.read!()
        |> :crypto.hash(:sha256)
        |> Base.encode16(case: :lower)
      end
    end
    """

    expected = """
    defmodule PipeSwappedCryptoHash do
      @moduledoc "Demonstrates piping file contents into :crypto.hash with swapped args."

      def hash_file(path) do
        :crypto.hash(
          :sha256,
          path
          |> File.read!()
        )
        |> Base.encode16(case: :lower)
      end
    end
    """

    confirm_fix(fix(input, @match_message, 7), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule PipeSwappedCryptoHash do
      @moduledoc "Demonstrates piping file contents into :crypto.hash with swapped args."

      def hash_file(path) do
        path
        |> File.read!()
        |> :crypto.hash(:sha256)
        |> Base.encode16(case: :lower)
      end
    end
    """

    assert valid_syntax?(fix(input, @match_message, 7))
  end

  test "returns source unchanged when no pipe into crypto.hash" do
    input = """
    defmodule CleanExample do
      def hash_data(data) do
        :crypto.hash(:sha256, data)
      end
    end
    """

    confirm_fix(fix(input, @match_message, 3), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @match_message), input)
  end
end
