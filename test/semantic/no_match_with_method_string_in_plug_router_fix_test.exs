defmodule Credence.Semantic.NoMatchWithMethodStringInPlugRouterFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoMatchWithMethodStringInPlugRouter
  alias Credence.RuleHelpers

  @matching_msg "no function clause matching in Access.get/3"

  defp fix(source, line \\ 0) do
    NoMatchWithMethodStringInPlugRouter.fix(source, %{
      severity: :error,
      message: @matching_msg,
      position: {line, 1}
    })
  end

  test "real Plug.Router diagnostic is dispatched and repaired by the Semantic pipeline" do
    input = """
    defmodule NoMatchWithMethodStringPipelineFixture do
      use Plug.Router

      plug :match
      plug :dispatch

      match "POST", "/api/webhooks/stripe" do
        send_resp(conn, 200, "ok")
      end
    end
    """

    expected = """
    defmodule NoMatchWithMethodStringPipelineFixture do
      use Plug.Router

      plug(:match)
      plug(:dispatch)

      post "/api/webhooks/stripe" do
        send_resp(conn, 200, "ok")
      end
    end
    """

    control = """
    defmodule NoMatchWithMethodStringPipelineControl do
      use Plug.Router

      plug(:match)
      plug(:dispatch)

      post "/api/webhooks/stripe" do
        send_resp(conn, 200, "ok")
      end
    end
    """

    assert {:error, diagnostics} = RuleHelpers.compile_and_capture(input)
    assert Enum.any?(diagnostics, &NoMatchWithMethodStringInPlugRouter.match?/1)

    {emitted, applied} = Credence.Semantic.fix_with_trace(input)
    confirm_fix(emitted, String.trim_trailing(expected))
    assert applied == [{NoMatchWithMethodStringInPlugRouter, 1}]
    assert {:ok, []} = RuleHelpers.compile_and_capture(emitted)
    assert {:ok, []} = RuleHelpers.compile_and_capture(control)
  end

  test "fixes match POST to post macro" do
    input = """
    defmodule ExampleRouter do
      use Plug.Router

      plug :match
      plug :dispatch

      match "POST", "/api/webhooks/stripe" do
        send_resp(conn, 200, "ok")
      end

      match _ do
        send_resp(conn, 404, "not found")
      end
    end
    """

    expected = """
    defmodule ExampleRouter do
      use Plug.Router

      plug(:match)
      plug(:dispatch)

      post "/api/webhooks/stripe" do
        send_resp(conn, 200, "ok")
      end

      match _ do
        send_resp(conn, 404, "not found")
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes match GET to get macro" do
    input = """
    defmodule MyRouter do
      use Plug.Router

      match "GET", "/api/users" do
        send_resp(conn, 200, "users")
      end
    end
    """

    expected = """
    defmodule MyRouter do
      use Plug.Router

      get "/api/users" do
        send_resp(conn, 200, "users")
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes match PUT to put macro" do
    input = """
    defmodule R do
      use Plug.Router

      match "PUT", "/api/items/:id" do
        send_resp(conn, 200, "updated")
      end
    end
    """

    expected = """
    defmodule R do
      use Plug.Router

      put "/api/items/:id" do
        send_resp(conn, 200, "updated")
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes match PATCH to patch macro" do
    input = """
    defmodule R do
      use Plug.Router

      match "PATCH", "/api/items/:id" do
        send_resp(conn, 200, "patched")
      end
    end
    """

    expected = """
    defmodule R do
      use Plug.Router

      patch "/api/items/:id" do
        send_resp(conn, 200, "patched")
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes match DELETE to delete macro" do
    input = """
    defmodule R do
      use Plug.Router

      match "DELETE", "/api/items/:id" do
        send_resp(conn, 200, "deleted")
      end
    end
    """

    expected = """
    defmodule R do
      use Plug.Router

      delete "/api/items/:id" do
        send_resp(conn, 200, "deleted")
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "leaves match _ unchanged" do
    input = """
    defmodule R do
      use Plug.Router

      match _ do
        send_resp(conn, 404, "not found")
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "leaves unknown method string unchanged" do
    input = """
    defmodule R do
      use Plug.Router

      match "OPTIONS", "/api/resource" do
        send_resp(conn, 200, "ok")
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "fixes only the diagnostic line in a Plug.Router module" do
    input = """
    defmodule TargetRouterNMWMSIPR do
      use Plug.Router

      match "POST", "/target" do
        send_resp(conn, 200, "target")
      end

      match "GET", "/other" do
        send_resp(conn, 200, "other")
      end
    end

    defmodule UnrelatedMatchMacroNMWMSIPR do
      match "DELETE", "/unrelated" do
        :not_a_plug_route
      end
    end
    """

    expected = """
    defmodule TargetRouterNMWMSIPR do
      use Plug.Router

      post "/target" do
        send_resp(conn, 200, "target")
      end

      match "GET", "/other" do
        send_resp(conn, 200, "other")
      end
    end

    defmodule UnrelatedMatchMacroNMWMSIPR do
      match "DELETE", "/unrelated" do
        :not_a_plug_route
      end
    end
    """

    confirm_fix(fix(input, 4), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule ExampleRouter do
      use Plug.Router

      match "POST", "/api/webhooks/stripe" do
        send_resp(conn, 200, "ok")
      end
    end
    """

    assert valid_syntax?(fix(input))
  end
end
