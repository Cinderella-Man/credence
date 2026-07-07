defmodule Credence.Semantic.FixNestedModuleShortReferenceFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixNestedModuleShortReference

  @message "redefining module WorkStealQueue (current version loaded from _build/test/lib/workspace/ebin/Elixir.WorkStealQueue.beam)"

  defp fix(source, message, line \\ 1) do
    FixNestedModuleShortReference.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes the source" do
    input = """
    defmodule WorkStealQueue do
      def run do
        {:ok, pid} = Coordinator.start_link()
        Coordinator.get_state(pid)
      end

      defmodule Coordinator do
        def start_link, do: Agent.start_link(fn -> %{} end)
        def get_state(pid), do: Agent.get(pid, & &1)
      end
    end
    """

    expected = """
    defmodule WorkStealQueue do
      def run do
        {:ok, pid} = WorkStealQueue.Coordinator.start_link()
        WorkStealQueue.Coordinator.get_state(pid)
      end

      defmodule Coordinator do
        def start_link, do: Agent.start_link(fn -> %{} end)
        def get_state(pid), do: Agent.get(pid, & &1)
      end
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule WorkStealQueue do
      def run do
        {:ok, pid} = Coordinator.start_link()
        Coordinator.get_state(pid)
      end

      defmodule Coordinator do
        def start_link, do: Agent.start_link(fn -> %{} end)
        def get_state(pid), do: Agent.get(pid, & &1)
      end
    end
    """

    assert valid_syntax?(fix(input, @message))
  end
end
