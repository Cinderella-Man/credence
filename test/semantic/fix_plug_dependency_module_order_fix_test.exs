defmodule Credence.Semantic.FixPlugDependencyModuleOrderFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixPlugDependencyModuleOrder

  @diag_message "function MediaVersionApi.Plugs.AcceptVersion.init/1 is undefined (module MediaVersionApi.Plugs.AcceptVersion is not available)"

  defp fix(source, message \\ @diag_message, line \\ 0) do
    FixPlugDependencyModuleOrder.fix(source, %{
      severity: :error,
      message: message,
      position: line
    })
  end

  test "reorders modules so dependency comes first" do
    input = ~S"""
    defmodule MediaVersionApi.Router do
      use Plug.Router
      import Plug.Conn

      plug(MediaVersionApi.Plugs.AcceptVersion)
      plug(:match)
      plug(:dispatch)

      get "/hello" do
        send_resp(conn, 200, "world")
      end
    end

    defmodule MediaVersionApi.Plugs.AcceptVersion do
      @behaviour Plug

      @impl true
      def init(opts), do: opts

      @impl true
      def call(conn, _opts), do: conn
    end
    """

    expected = ~S"""
    defmodule MediaVersionApi.Plugs.AcceptVersion do
      @behaviour Plug

      @impl true
      def init(opts), do: opts

      @impl true
      def call(conn, _opts), do: conn
    end

    defmodule MediaVersionApi.Router do
      use Plug.Router
      import Plug.Conn

      plug(MediaVersionApi.Plugs.AcceptVersion)
      plug(:match)
      plug(:dispatch)

      get "/hello" do
        send_resp(conn, 200, "world")
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule Foo.Router do
      use Plug.Router

      plug(Foo.Plugs.Bar)
      plug(:match)
      plug(:dispatch)

      match _ do
        send_resp(conn, 200, "ok")
      end
    end

    defmodule Foo.Plugs.Bar do
      def init(opts), do: opts
      def call(conn, _opts), do: conn
    end
    """

    message = "function Foo.Plugs.Bar.init/1 is undefined (module Foo.Plugs.Bar is not available)"
    assert valid_syntax?(fix(input, message))
  end

  test "returns source unchanged when dependency already comes first" do
    input = ~S"""
    defmodule MediaVersionApi.Plugs.AcceptVersion do
      @behaviour Plug

      @impl true
      def init(opts), do: opts

      @impl true
      def call(conn, _opts), do: conn
    end

    defmodule MediaVersionApi.Router do
      use Plug.Router
      import Plug.Conn

      plug(MediaVersionApi.Plugs.AcceptVersion)
      plug(:match)
      plug(:dispatch)
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged when message does not match" do
    input = """
    defmodule A do
    end

    defmodule B do
    end
    """

    confirm_fix(fix(input, "some unrelated error"), input)
  end

  test "reorders correctly when the router contains a nested helper module before the plug call" do
    input = ~S"""
    defmodule Foo.Router do
      defmodule Helper do
        def status, do: :ok
      end

      use Plug.Router

      plug(Foo.Plugs.Bar)
      plug(:match)
      plug(:dispatch)
    end

    defmodule Foo.Plugs.Bar do
      def init(opts), do: opts
      def call(conn, _opts), do: conn
    end
    """

    expected = ~S"""
    defmodule Foo.Plugs.Bar do
      def init(opts), do: opts
      def call(conn, _opts), do: conn
    end

    defmodule Foo.Router do
      defmodule Helper do
        def status, do: :ok
      end

      use Plug.Router

      plug(Foo.Plugs.Bar)
      plug(:match)
      plug(:dispatch)
    end
    """

    message = "function Foo.Plugs.Bar.init/1 is undefined (module Foo.Plugs.Bar is not available)"
    confirm_fix(fix(input, message), expected)
  end

  test "returns source unchanged when the dependency is nested inside the router" do
    input = ~S"""
    defmodule Foo.Router do
      use Plug.Router

      plug(Foo.Plugs.Bar)
      plug(:match)
      plug(:dispatch)

      defmodule Foo.Plugs.Bar do
        def init(opts), do: opts
        def call(conn, _opts), do: conn
      end
    end
    """

    message = "function Foo.Plugs.Bar.init/1 is undefined (module Foo.Plugs.Bar is not available)"
    confirm_fix(fix(input, message), input)
  end

  test "returns source unchanged when the dependency module is not defined in the file" do
    input = ~S"""
    defmodule Foo.Router do
      use Plug.Router

      plug(Foo.Plugs.Bar)
      plug(:match)
      plug(:dispatch)
    end
    """

    message = "function Foo.Plugs.Bar.init/1 is undefined (module Foo.Plugs.Bar is not available)"
    confirm_fix(fix(input, message), input)
  end

  test "reorders modules when plug uses short alias after alias declaration" do
    input = ~S"""
    defmodule LifecycleApi.Router do
      use Plug.Router

      import Plug.Conn

      alias LifecycleApi.Plugs.ApiVersion

      plug :match
      plug :fetch_query_params
      plug :fetch_headers
      plug(ApiVersion, default: "v2")
      plug :dispatch

      get "/api/users/:id" do
        conn |> send_resp(200, "ok")
      end
    end

    defmodule LifecycleApi.Plugs.ApiVersion do
      @moduledoc false
      def init(opts), do: opts

      def call(conn, _opts), do: conn
    end
    """

    expected = ~S"""
    defmodule LifecycleApi.Plugs.ApiVersion do
      @moduledoc false
      def init(opts), do: opts

      def call(conn, _opts), do: conn
    end

    defmodule LifecycleApi.Router do
      use Plug.Router

      import Plug.Conn

      alias LifecycleApi.Plugs.ApiVersion

      plug :match
      plug :fetch_query_params
      plug :fetch_headers
      plug(ApiVersion, default: "v2")
      plug :dispatch

      get "/api/users/:id" do
        conn |> send_resp(200, "ok")
      end
    end
    """

    message =
      "function LifecycleApi.Plugs.ApiVersion.init/1 is undefined (module LifecycleApi.Plugs.ApiVersion is not available)"

    confirm_fix(fix(input, message), expected)
  end

  # Mutation gap (D9 triage): `find_plug_caller/2`'s `Enum.with_index(lines, 1)` could be
  # changed to `2` and every existing fixture still passed. The index is used to ask which
  # module ENCLOSES the `plug` line, so a +1 only escapes the range when the `plug` call is
  # the module's LAST body line — the next line being its `end`. No fixture had that shape,
  # so the rule's containment lookup was untested at its only boundary.
  #
  # Verified by applying the mutant: original reorders, mutant leaves the source alone.
  test "the plug call as the module's last body line still finds its enclosing module" do
    input = ~S"""
    defmodule Foo.Router do
      use Plug.Router
      plug(Foo.Plugs.Bar)
    end

    defmodule Foo.Plugs.Bar do
      def init(opts), do: opts
    end
    """

    expected = ~S"""
    defmodule Foo.Plugs.Bar do
      def init(opts), do: opts
    end

    defmodule Foo.Router do
      use Plug.Router
      plug(Foo.Plugs.Bar)
    end
    """

    message = "function Foo.Plugs.Bar.init/1 is undefined (module Foo.Plugs.Bar is not available)"

    confirm_fix(fix(input, message), expected)
    assert valid_syntax?(fix(input, message))
  end
end
