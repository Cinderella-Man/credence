defmodule Credence.Semantic.NoBareFunctionDefSyntaxFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoBareFunctionDefSyntax

  @bare_init ~S'''
  defmodule Foo do
    use Plug.Router

    plug :match
    plug :dispatch

    init(opts) do
      opts
    end

    get "/ping" do
      send_resp(conn, 200, "pong")
    end
  end
  '''

  @fixed_init ~S'''
  defmodule Foo do
    use Plug.Router

    plug :match
    plug :dispatch

    def init(opts) do
      opts
    end

    get "/ping" do
      send_resp(conn, 200, "pong")
    end
  end
  '''

  defp fix(source, message, line) do
    NoBareFunctionDefSyntax.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes bare init in Plug.Router" do
    message = "undefined function init/2 (there is no such import)"
    confirm_fix(fix(@bare_init, message, 7), @fixed_init)
  end

  test "fixed output is well-formed (parses)" do
    message = "undefined function init/2 (there is no such import)"
    assert valid_syntax?(fix(@bare_init, message, 7))
  end

  test "ignores lines that already have def" do
    already_def = ~S'''
    defmodule Foo do
      def init(opts) do
        opts
      end
    end
    '''

    message = "undefined function init/2 (there is no such import)"
    # Line 2 already has `def`, so the bare regex won't match
    confirm_fix(fix(already_def, message, 2), already_def)
  end

  test "ignores lines without do block" do
    call_only = ~S'''
    defmodule Foo do
      def bar do
        init(opts)
      end
    end
    '''

    message = "undefined function init/2 (there is no such import)"
    # Line 3 is a call without `do`, not a bare function def
    confirm_fix(fix(call_only, message, 3), call_only)
  end

  test "does not fix return/1 (hallucinated keyword, not a bare function def)" do
    source = """
    defmodule M do
      def f do
        unless true do
          return {:error, :bad}
        end
        :ok
      end
    end
    """

    message = "undefined function return/1"
    # Line 4 is `return {:error, :bad}` — not a bare function def, no `do` block
    confirm_fix(fix(source, message, 4), source)
  end
end
