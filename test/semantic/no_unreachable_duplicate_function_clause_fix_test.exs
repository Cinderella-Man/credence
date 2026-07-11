defmodule Credence.Semantic.NoUnreachableDuplicateFunctionClauseFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoUnreachableDuplicateFunctionClause

  @real_msg "no match of right hand side value:\n\n    [:notifications_server, :timeout_ms]\n"

  defp fix(source, message \\ @real_msg, line \\ 1) do
    NoUnreachableDuplicateFunctionClause.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "removes unreachable duplicate def clause" do
    input = """
    defmodule Notifications do
      use GenServer

      def start_link(opts) do
        name = Keyword.get(opts, :name, __MODULE__)
        GenServer.start_link(__MODULE__, [], name: name)
      end

      @impl true
      def init(_opts) do
        {:ok, %{}}
      end

      defp ensure_registry_started do
        :ok
      end

      def start_link(opts) do
        ensure_registry_started()
        name = Keyword.get(opts, :name, __MODULE__)
        GenServer.start_link(__MODULE__, [], name: name)
      end
    end
    """

    expected = """
    defmodule Notifications do
      use GenServer

      def start_link(opts) do
        name = Keyword.get(opts, :name, __MODULE__)
        GenServer.start_link(__MODULE__, [], name: name)
      end

      @impl true
      def init(_opts) do
        {:ok, %{}}
      end

      defp ensure_registry_started do
        :ok
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Notifications do
      def start_link(opts) do
        :ok
      end

      def start_link(opts) do
        :error
      end
    end
    """

    assert valid_syntax?(fix(input))
  end
end
