defmodule Credence.Semantic.FixUndefinedParamsInPlugRouterFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixUndefinedParamsInPlugRouter

  @real_message "undefined variable \"params\""

  defp fix(source, message, line \\ 1) do
    FixUndefinedParamsInPlugRouter.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes params access in a Plug.Router route handler" do
    input = """
    defmodule WebhookReceiver.Router do
      use Plug.Router

      plug :match
      plug :dispatch

      post "/api/webhooks/:provider" do
        provider = params["provider"]

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{provider: provider}))
        |> halt()
      end

      match _ do
        send_resp(conn, 404, "not found")
      end
    end
    """

    expected = """
    defmodule WebhookReceiver.Router do
      use Plug.Router

      plug :match
      plug :dispatch

      post "/api/webhooks/:provider" do
        provider = conn.params["provider"]

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{provider: provider}))
        |> halt()
      end

      match _ do
        send_resp(conn, 404, "not found")
      end
    end
    """

    confirm_fix(fix(input, @real_message, 8), expected)
  end

  test "fixes params access with atom key" do
    input = """
    defmodule MyRouter do
      use Plug.Router

      plug :match
      plug :dispatch

      get "/data" do
        value = params[:id]
        send_resp(conn, 200, value)
      end
    end
    """

    expected = """
    defmodule MyRouter do
      use Plug.Router

      plug :match
      plug :dispatch

      get "/data" do
        value = conn.params[:id]
        send_resp(conn, 200, value)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 8), expected)
  end

  test "fixes multiple params accesses on the same line" do
    input = ~S'result = params["a"] <> params["b"]'
    expected = ~S'result = conn.params["a"] <> conn.params["b"]'
    confirm_fix(fix(input, @real_message), expected)
  end

  test "does not modify conn.params that is already correct" do
    input = """
    defmodule MyRouter do
      use Plug.Router

      plug :match
      plug :dispatch

      get "/ok" do
        value = conn.params["id"]
        send_resp(conn, 200, value)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 8), input)
  end

  test "returns source unchanged for unrelated message" do
    input = """
    defmodule MyRouter do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, "unrelated"), input)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule WebhookReceiver.Router do
      use Plug.Router

      plug :match
      plug :dispatch

      post "/api/webhooks/:provider" do
        provider = params["provider"]
        send_resp(conn, 200, provider)
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message, 8))
  end
end
