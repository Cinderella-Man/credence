defmodule Credence.Semantic.NoUsePlugConnFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Semantic.NoUsePlugConn

  @diag %{
    severity: :error,
    message: "function Plug.Conn.__using__/1 is undefined or private",
    position: 0,
    file: "credence_check.ex"
  }

  defp fix(source), do: NoUsePlugConn.fix(source, @diag)

  test "rewrites `use Plug.Conn` to `import Plug.Conn`" do
    input = """
    defmodule MyApp.Plug.Greeter do
      use Plug.Conn

      def call(conn, _opts) do
        send_resp(conn, 200, "ok")
      end
    end
    """

    expected = """
    defmodule MyApp.Plug.Greeter do
      import Plug.Conn

      def call(conn, _opts) do
        send_resp(conn, 200, "ok")
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "keeps a trailing comment on the rewritten line" do
    input = """
    defmodule MyApp.Plug.Greeter do
      use Plug.Conn  # needed for send_resp/3
    end
    """

    expected = """
    defmodule MyApp.Plug.Greeter do
      import Plug.Conn  # needed for send_resp/3
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "rewrites every module in the file" do
    input = """
    defmodule MyApp.Plug.A do
      use Plug.Conn
    end

    defmodule MyApp.Plug.B do
      use Plug.Conn
    end
    """

    expected = """
    defmodule MyApp.Plug.A do
      import Plug.Conn
    end

    defmodule MyApp.Plug.B do
      import Plug.Conn
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "does not rewrite a quoted `use Plug.Conn` alongside an executable one" do
    input = """
    defmodule CredenceNoUsePlugConnQuotedFixProbe do
      use Plug.Conn

      def quoted do
        quote do
          use Plug.Conn
        end
      end
    end
    """

    expected = """
    defmodule CredenceNoUsePlugConnQuotedFixProbe do
      import Plug.Conn

      def quoted do
        quote do
          use Plug.Conn
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "semantic pipeline repairs the compiler's real Plug.Conn exception" do
    input = """
    defmodule CredenceNoUsePlugConnSemanticPipelineProbe do
      use Plug.Conn

      def call(conn, _opts), do: send_resp(conn, 200, "ok")
    end
    """

    expected = """
    defmodule CredenceNoUsePlugConnSemanticPipelineProbe do
      import Plug.Conn

      def call(conn, _opts), do: send_resp(conn, 200, "ok")
    end
    """

    assert {:error, [diagnostic]} = Credence.RuleHelpers.compile_and_capture(input)
    assert diagnostic.message == "function Plug.Conn.__using__/1 is undefined or private"
    assert NoUsePlugConn.match?(diagnostic)

    emitted = Credence.Semantic.fix(input)

    confirm_fix(emitted, expected)

    emitted_result = Credence.RuleHelpers.compile_and_capture(emitted)
    control_result = Credence.RuleHelpers.compile_and_capture(expected)

    assert emitted_result == control_result
    assert emitted_result == {:ok, []}
  end

  test "leaves the rest of the module byte-identical" do
    input = """
    defmodule MyApp.Plug.Greeter do
      @moduledoc \"\"\"
      Never write

          use Plug.Conn
      \"\"\"
      use Plug.Router
      use Plug.Conn

      # do not write `use Plug.Conn` here either
      plug(:match)

      def call(conn, _opts), do: send_resp(conn, 200, "use Plug.Conn")
    end
    """

    expected = """
    defmodule MyApp.Plug.Greeter do
      @moduledoc \"\"\"
      Never write

          use Plug.Conn
      \"\"\"
      use Plug.Router
      import Plug.Conn

      # do not write `use Plug.Conn` here either
      plug(:match)

      def call(conn, _opts), do: send_resp(conn, 200, "use Plug.Conn")
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "rewrites only the `Plug.Conn` use, not its neighbours" do
    input = """
    defmodule MyApp.Plug.Greeter do
      use Plug.Conn
      use Plug.Conn.Status
      use Plug.ConnTest
    end
    """

    expected = """
    defmodule MyApp.Plug.Greeter do
      import Plug.Conn
      use Plug.Conn.Status
      use Plug.ConnTest
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "is idempotent" do
    input = """
    defmodule MyApp.Plug.Greeter do
      use Plug.Conn
    end
    """

    once = fix(input)
    confirm_fix(fix(once), once)
  end

  test "fixed output parses" do
    input = """
    defmodule MyApp.Plug.Greeter do
      use Plug.Conn
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "leaves `use Plug.ConnTest` alone" do
    code = """
    defmodule MyApp.Plug.GreeterTest do
      use Plug.ConnTest
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves `use Plug.Conn.Status` alone" do
    code = """
    defmodule MyApp.Plug.Greeter do
      use Plug.Conn.Status
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves `use MyApp.Plug.Conn` alone" do
    code = """
    defmodule MyApp.Plug.Greeter do
      use MyApp.Plug.Conn
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves `use Plug.Conn` with options alone" do
    code = """
    defmodule MyApp.Plug.Greeter do
      use Plug.Conn, only: [:send_resp]
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves a `use` sharing its line with other code alone" do
    code = """
    defmodule MyApp.Plug.Greeter do
      use Plug.Conn; def init(opts), do: opts
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves `use(Plug.Conn)` alone" do
    code = """
    defmodule MyApp.Plug.Greeter do
      use(Plug.Conn)
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves an aliased `use Conn` alone" do
    code = """
    defmodule MyApp.Plug.Greeter do
      alias Plug.Conn
      use Conn
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves text mentioning `use Plug.Conn` alone" do
    code = """
    defmodule MyApp.Plug.Greeter do
      @moduledoc \"\"\"
      Do not write

          use Plug.Conn
      \"\"\"

      # never write: use Plug.Conn
      def call(conn, _opts), do: conn
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves unparseable source alone" do
    code = """
    defmodule Broken do
      use Plug.Conn
    """

    confirm_fix(fix(code), code)
  end
end
