defmodule Credence.Semantic.NoUsePlugConnCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Semantic.NoUsePlugConn

  # What `Credence.RuleHelpers.compile_and_capture/1` hands the semantic round
  # for this error: `use Plug.Conn` makes the compiler *raise*, so the
  # diagnostic is synthesized from the exception and carries no line (`0`).
  @diag %{
    severity: :error,
    message: "function Plug.Conn.__using__/1 is undefined or private",
    position: 0,
    file: "credence_check.ex"
  }

  @fixable """
  defmodule MyApp.Plug.Greeter do
    use Plug.Conn

    def call(conn, _opts) do
      send_resp(conn, 200, "ok")
    end
  end
  """

  test "matches the diagnostic" do
    assert NoUsePlugConn.match?(@diag)
  end

  test "matches the diagnostic when it carries a {line, col} position" do
    assert NoUsePlugConn.match?(%{@diag | position: {2, 3}})
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoUsePlugConn.match?(diag)
  end

  test "ignores the same error for a different module" do
    diag = %{@diag | message: "function MyApp.Plug.Conn.__using__/1 is undefined or private"}
    refute NoUsePlugConn.match?(diag)
  end

  test "ignores a diagnostic without a message" do
    refute NoUsePlugConn.match?(%{severity: :error, position: 0})
  end

  test "attributes the issue to this rule" do
    assert NoUsePlugConn.to_issue(@diag).rule == :no_use_plug_conn
  end

  test "reports the line the diagnostic carries" do
    assert NoUsePlugConn.to_issue(@diag).meta == %{line: 0}
    assert NoUsePlugConn.to_issue(%{@diag | position: {2, 3}}).meta == %{line: 2}
  end

  test "no other semantic rule claims this diagnostic first" do
    winner = Enum.find(Credence.Semantic.default_rules(), & &1.match?(@diag))
    assert winner == NoUsePlugConn
  end

  test "reports a `use Plug.Conn` statement" do
    assert NoUsePlugConn.should_report?(@diag, @fixable)
  end

  test "no issue for `use Plug.ConnTest` (a different module)" do
    source = """
    defmodule MyApp.Plug.GreeterTest do
      use Plug.ConnTest
    end
    """

    refute NoUsePlugConn.should_report?(@diag, source)
  end

  test "no issue for `use Plug.Conn.Status` (a different module)" do
    source = """
    defmodule MyApp.Plug.Greeter do
      use Plug.Conn.Status
    end
    """

    refute NoUsePlugConn.should_report?(@diag, source)
  end

  test "no issue for `use MyApp.Plug.Conn` (a different module)" do
    source = """
    defmodule MyApp.Plug.Greeter do
      use MyApp.Plug.Conn
    end
    """

    refute NoUsePlugConn.should_report?(@diag, source)
  end

  test "no issue when `use Plug.Conn` only appears in text" do
    source = """
    defmodule MyApp.Plug.Greeter do
      @moduledoc \"\"\"
      Do not write

          use Plug.Conn
      \"\"\"

      # never write: use Plug.Conn
      def call(conn, _opts), do: conn
    end
    """

    refute NoUsePlugConn.should_report?(@diag, source)
  end

  test "no issue for `use Plug.Conn` with options (import takes no such options)" do
    source = """
    defmodule MyApp.Plug.Greeter do
      use Plug.Conn, only: [:send_resp]
    end
    """

    refute NoUsePlugConn.should_report?(@diag, source)
  end

  test "no issue for a `use` that does not stand alone on its line" do
    source = """
    defmodule MyApp.Plug.Greeter do
      def call(conn, _opts), do: conn
      use Plug.Conn; def init(opts), do: opts
    end
    """

    refute NoUsePlugConn.should_report?(@diag, source)
  end

  test "no issue for `use(Plug.Conn)`" do
    source = """
    defmodule MyApp.Plug.Greeter do
      use(Plug.Conn)
    end
    """

    refute NoUsePlugConn.should_report?(@diag, source)
  end

  test "no issue for an aliased `use Conn`" do
    source = """
    defmodule MyApp.Plug.Greeter do
      alias Plug.Conn
      use Conn
    end
    """

    refute NoUsePlugConn.should_report?(@diag, source)
  end

  test "no issue when the source does not parse" do
    refute NoUsePlugConn.should_report?(@diag, "defmodule Broken do\n  use Plug.Conn\n")
  end
end
