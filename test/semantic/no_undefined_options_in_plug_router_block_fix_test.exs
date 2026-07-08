defmodule Credence.Semantic.NoUndefinedOptionsInPlugRouterBlockFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoUndefinedOptionsInPlugRouterBlock

  @real_message "undefined variable \"options\""

  defp fix(source, message, line \\ 1) do
    NoUndefinedOptionsInPlugRouterBlock.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "inserts options binding at the start of the route handler block" do
    input = """
    defmodule Example.Router do
      use Plug.Router
      plug :match
      plug :dispatch

      post "/webhook" do
        store = Keyword.get(options, :store)
        secret = Keyword.get(options, :secret)
        send_resp(conn, 200, "ok")
      end
    end
    """

    expected = """
    defmodule Example.Router do
      use Plug.Router
      plug :match
      plug :dispatch

      post "/webhook" do
        options = conn.private[:plug_router_opts]
        store = Keyword.get(options, :store)
        secret = Keyword.get(options, :secret)
        send_resp(conn, 200, "ok")
      end
    end
    """

    confirm_fix(fix(input, @real_message, 7), expected)
  end

  test "works for get handler" do
    input = """
    defmodule Example.Router do
      use Plug.Router
      plug :match
      plug :dispatch

      get "/status" do
        mode = Keyword.get(options, :mode)
        send_resp(conn, 200, mode)
      end
    end
    """

    expected = """
    defmodule Example.Router do
      use Plug.Router
      plug :match
      plug :dispatch

      get "/status" do
        options = conn.private[:plug_router_opts]
        mode = Keyword.get(options, :mode)
        send_resp(conn, 200, mode)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 7), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example.Router do
      use Plug.Router
      plug :match
      plug :dispatch

      post "/webhook" do
        store = Keyword.get(options, :store)
        send_resp(conn, 200, "ok")
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message, 7))
  end

  test "returns source unchanged when no route handler at line" do
    input = """
    defmodule Example.Router do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message, 1), input)
  end

  test "returns source unchanged for unrelated message" do
    input = """
    defmodule Example.Router do
      use Plug.Router
      plug :match
      plug :dispatch

      post "/webhook" do
        store = Keyword.get(options, :store)
        send_resp(conn, 200, "ok")
      end
    end
    """

    confirm_fix(fix(input, "unrelated", 7), input)
  end
end
