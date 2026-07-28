defmodule Credence.Pattern.NoCryptoHashPipeSwappedArgsFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoCryptoHashPipeSwappedArgs

  test "rewrites the pipe into a direct call with the arguments in order" do
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

    confirm_fix(fix(NoCryptoHashPipeSwappedArgs, input), expected)
  end

  test "a single-stage pipe collapses to one line" do
    input = """
    defmodule OneStage do
      def digest(data) do
        data
        |> :crypto.hash(:sha256)
      end
    end
    """

    expected = """
    defmodule OneStage do
      def digest(data) do
        :crypto.hash(:sha256, data)
      end
    end
    """

    confirm_fix(fix(NoCryptoHashPipeSwappedArgs, input), expected)
  end

  test "leaves the correct argument order unchanged" do
    input = """
    defmodule CleanExample do
      def hash_data(data) do
        :crypto.hash(:sha256, data)
      end
    end
    """

    confirm_fix(fix(NoCryptoHashPipeSwappedArgs, input), input)
  end

  test "leaves a two-argument pipe unchanged" do
    input = """
    defmodule TwoArg do
      def hash_data(data, salt) do
        data
        |> :crypto.hash(:sha256, salt)
      end
    end
    """

    confirm_fix(fix(NoCryptoHashPipeSwappedArgs, input), input)
  end

  test "output parses" do
    input = """
    defmodule ParsesAfterFix do
      def hash_file(path) do
        path
        |> File.read!()
        |> :crypto.hash(:sha256)
        |> Base.encode16(case: :lower)
      end
    end
    """

    assert valid_syntax?(fix(NoCryptoHashPipeSwappedArgs, input))
  end
end
