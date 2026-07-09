defmodule Credence.Syntax.NoBareAtomInGenserverStartLinkAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoBareAtomInGenserverStartLink

  defp analyze(code), do: NoBareAtomInGenserverStartLink.analyze(code)

  test "flags GenServer.start_link with || fallback bare atom" do
    code = """
    defmodule MyGenServer do
      use GenServer

      def start_link(opts) do
        GenServer.start_link(__MODULE__, :ok, opts[:name] || __MODULE__)
      end
    end
    """

    assert [%Issue{rule: :no_bare_atom_in_genserver_start_link}] = analyze(code)
  end

  test "flags GenServer.start_link with bare atom third arg" do
    code = """
    defmodule MyGenServer do
      use GenServer

      def start_link do
        GenServer.start_link(__MODULE__, :ok, __MODULE__)
      end
    end
    """

    assert [%Issue{rule: :no_bare_atom_in_genserver_start_link}] = analyze(code)
  end

  test "leaves keyword list third arg alone" do
    code = """
    defmodule MyGenServer do
      use GenServer

      def start_link(opts) do
        GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
      end
    end
    """

    assert analyze(code) == []
  end

  test "leaves empty list third arg alone" do
    code = """
    defmodule MyGenServer do
      use GenServer

      def start_link do
        GenServer.start_link(__MODULE__, :ok, [])
      end
    end
    """

    assert analyze(code) == []
  end

  test "leaves 2-arg call alone" do
    code = """
    defmodule MyGenServer do
      use GenServer

      def start_link do
        GenServer.start_link(__MODULE__, :ok)
      end
    end
    """

    assert analyze(code) == []
  end
end
