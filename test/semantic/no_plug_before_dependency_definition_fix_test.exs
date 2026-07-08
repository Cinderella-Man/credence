defmodule Credence.Semantic.NoPlugBeforeDependencyDefinitionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoPlugBeforeDependencyDefinition

  @diag_message "function LifecycleApi.Plugs.ApiVersion.init/1 is undefined (module LifecycleApi.Plugs.ApiVersion is not available)"

  defp fix(source, message \\ @diag_message, line \\ 0) do
    NoPlugBeforeDependencyDefinition.fix(source, %{
      severity: :error,
      message: message,
      position: line
    })
  end

  test "reorders modules so dependency comes first" do
    input = ~S"""
    defmodule LifecycleApi.Router do
      use Plug.Router
      import Plug.Conn

      plug LifecycleApi.Plugs.ApiVersion
      plug :match
      plug :dispatch

      get "/api/users/:id" do
        user = users()[conn.params["id"]]

        if user do
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{name: user.name}))
        else
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(404, Jason.encode!(%{error: "not found"}))
        end
      end

      match _ do
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not found"}))
      end

      defp users do
        %{
          "1" => %{name: "Alice"}
        }
      end
    end

    defmodule LifecycleApi.Plugs.ApiVersion do
      import Plug.Conn

      def init(opts), do: opts

      def call(conn, _opts), do: conn
    end
    """

    expected = ~S"""
    defmodule LifecycleApi.Plugs.ApiVersion do
      import Plug.Conn

      def init(opts), do: opts

      def call(conn, _opts), do: conn
    end

    defmodule LifecycleApi.Router do
      use Plug.Router
      import Plug.Conn

      plug LifecycleApi.Plugs.ApiVersion
      plug :match
      plug :dispatch

      get "/api/users/:id" do
        user = users()[conn.params["id"]]

        if user do
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{name: user.name}))
        else
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(404, Jason.encode!(%{error: "not found"}))
        end
      end

      match _ do
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "not found"}))
      end

      defp users do
        %{
          "1" => %{name: "Alice"}
        }
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule Foo.Router do
      use Plug.Router

      plug Foo.Plugs.Bar
      plug :match
      plug :dispatch

      match _ do
        send_resp(conn, 200, "ok")
      end
    end

    defmodule Foo.Plugs.Bar do
      def init(opts), do: opts
      def call(conn, _opts), do: conn
    end
    """

    assert valid_syntax?(
             fix(
               input,
               "function Foo.Plugs.Bar.init/1 is undefined (module Foo.Plugs.Bar is not available)"
             )
           )
  end

  test "returns source unchanged when module name not in message" do
    input = """
    defmodule A do
    end

    defmodule B do
    end
    """

    confirm_fix(fix(input, "some unrelated error"), input)
  end

  test "returns source unchanged when dependency already comes first" do
    input = ~S"""
    defmodule LifecycleApi.Plugs.ApiVersion do
      import Plug.Conn

      def init(opts), do: opts

      def call(conn, _opts), do: conn
    end

    defmodule LifecycleApi.Router do
      use Plug.Router
      import Plug.Conn

      plug LifecycleApi.Plugs.ApiVersion
      plug :match
      plug :dispatch
    end
    """

    confirm_fix(fix(input), input)
  end
end
