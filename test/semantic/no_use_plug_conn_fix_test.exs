defmodule Credence.Semantic.NoUsePlugConnFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoUsePlugConn

  @message "function Plug.Conn.__using__/1 is undefined or private"

  defp fix(source, message \\ @message, line \\ 1) do
    NoUsePlugConn.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "fixes the source" do
    input = """
    defmodule MyApp.Poller do
      use Plug.Conn

      def call(conn, _opts) do
        send_resp(conn, 200, "ok")
      end
    end
    """

    expected = """
    defmodule MyApp.Poller do
      import Plug.Conn

      def call(conn, _opts) do
        send_resp(conn, 200, "ok")
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule MyApp.Poller do
      use Plug.Conn
    end
    """

    assert valid_syntax?(fix(input))
  end
end
