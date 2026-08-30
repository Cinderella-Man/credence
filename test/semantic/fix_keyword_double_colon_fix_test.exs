defmodule Credence.Semantic.FixKeywordDoubleColonFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixKeywordDoubleColon

  @message "misplaced operator ::/2"

  # All positions below are the real `Code.with_diagnostics/1` positions for
  # each fixture, not hand-counted columns.
  defp fix(source, line, col) do
    FixKeywordDoubleColon.fix(source, %{
      severity: :error,
      message: @message,
      position: {line, col}
    })
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

    confirm_fix(fix(input, 5, 47), expected)
    assert valid_syntax?(fix(input, 5, 47))
  end

  test "fixes interval::1_000, preserving the underscore literal" do
    input =
      """
      defmodule F do
        def f do
          Process.send_after(self(), :tick, interval::1_000)
        end
      end
      """

    expected =
      """
      defmodule F do
        def f do
          Process.send_after(self(), :tick, interval: 1_000)
        end
      end
      """

    confirm_fix(fix(input, 3, 47), expected)
  end

  test "fixes a keyword typo in a non-final argument when the result parses" do
    input =
      """
      defmodule C do
        def f do
          Keyword.get([a: 1], :a, default::5)
        end
      end
      """

    expected =
      """
      defmodule C do
        def f do
          Keyword.get([a: 1], :a, default: 5)
        end
      end
      """

    confirm_fix(fix(input, 3, 36), expected)
  end

  test "grapheme-aligned columns: combining accent earlier on the line" do
    input =
      """
      defmodule U3 do
        def f do
          foo("éx", name::M)
        end

        def foo(a, b), do: {a, b}
      end
      """

    expected =
      """
      defmodule U3 do
        def f do
          foo("éx", name: M)
        end

        def foo(a, b), do: {a, b}
      end
      """

    confirm_fix(fix(input, 3, 19), expected)
  end

  test "no-op on a non-keyword misplaced :: (fix would not parse)" do
    input =
      """
      defmodule A do
        def f(x) do
          y = x::integer
          y
        end
      end
      """

    confirm_fix(fix(input, 3, 10), input)
  end

  test "no-op when a second :: follows on the same line (fix would not parse)" do
    input =
      """
      defmodule D do
        def f do
          foo(a::1, b::2)
        end

        def foo(x), do: x
      end
      """

    confirm_fix(fix(input, 3, 10), input)
  end

  test "no-op on a spaced `name :: value` (fix would not parse)" do
    input =
      """
      defmodule E do
        def f do
          foo(name :: MyServer)
        end

        def foo(x), do: x
      end
      """

    confirm_fix(fix(input, 3, 14), input)
  end

  test "no-op when the column does not sit on a literal ::" do
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

    confirm_fix(fix(input, 5, 40), input)
  end

  test "no-op when the diagnostic line is out of range" do
    input =
      """
      defmodule M do
      end
      """

    confirm_fix(fix(input, 99, 1), input)
  end

  test "no-op on a line-only (no column) position" do
    input =
      """
      defmodule M do
        def f, do: foo(name::M)
      end
      """

    diag = %{severity: :error, message: @message, position: 2}
    confirm_fix(FixKeywordDoubleColon.fix(input, diag), input)
  end

  test "end-to-end: the semantic phase resolves the typo using the real diagnostic" do
    input =
      """
      defmodule CredenceKwDoubleColonE2EFixture do
        use GenServer

        def start do
          GenServer.start_link(__MODULE__, :ok, name::CredenceKwDoubleColonE2EName)
        end

        def init(state), do: {:ok, state}
      end
      """

    expected =
      """
      defmodule CredenceKwDoubleColonE2EFixture do
        use GenServer

        def start do
          GenServer.start_link(__MODULE__, :ok, name: CredenceKwDoubleColonE2EName)
        end

        def init(state), do: {:ok, state}
      end
      """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end
end
