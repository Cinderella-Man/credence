defmodule Credence.Syntax.NoBareAtomInGenserverStartLinkFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoBareAtomInGenserverStartLink

  defp analyze(code), do: NoBareAtomInGenserverStartLink.analyze(code)
  defp fix(code), do: NoBareAtomInGenserverStartLink.fix(code)

  test "fixes opts[:name] || __MODULE__ pattern" do
    input = """
    defmodule MyGenServer do
      use GenServer

      def start_link(opts) do
        GenServer.start_link(__MODULE__, :ok, opts[:name] || __MODULE__)
      end
    end
    """

    expected = """
    defmodule MyGenServer do
      use GenServer

      def start_link(opts) do
        GenServer.start_link(__MODULE__, :ok, if(opts[:name], do: [name: opts[:name]], else: []))
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = """
    defmodule MyGenServer do
      use GenServer

      def start_link(opts) do
        GenServer.start_link(__MODULE__, :ok, opts[:name] || __MODULE__)
      end
    end
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule MyGenServer do
      use GenServer

      def start_link(opts) do
        GenServer.start_link(__MODULE__, :ok, opts[:name] || __MODULE__)
      end
    end
    """

    assert valid_syntax?(fix(input))
  end
end
