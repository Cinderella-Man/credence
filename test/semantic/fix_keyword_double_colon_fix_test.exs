defmodule Credence.Semantic.FixKeywordDoubleColonFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixKeywordDoubleColon

  @message "misplaced operator ::/2"

  defp fix(source, message, line, col) do
    FixKeywordDoubleColon.fix(source, %{severity: :error, message: message, position: {line, col}})
  end

  test "fixes name::MyServer to name: MyServer" do
    input =
      """
      defmodule M do
        use GenServer

        def start do
          GenServer.start_link(__MODULE__, :ok, name::MyServer)
        end

        def init(state), do: {:ok, state}
      end
      """

    expected =
      """
      defmodule M do
        use GenServer

        def start do
          GenServer.start_link(__MODULE__, :ok, name: MyServer)
        end

        def init(state), do: {:ok, state}
      end
      """

    confirm_fix(fix(input, @message, 5, 47), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = "GenServer.start_link(__MODULE__, :ok, name::MyServer)"
    assert valid_syntax?(fix(input, @message, 1, 43))
  end
end
