defmodule Credence.Semantic.NoBareReturnInGenserverInitFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoBareReturnInGenserverInit

  @match_msg "init/1 must return {:ok, state}"

  defp fix(source, message \\ @match_msg, line \\ 8) do
    NoBareReturnInGenserverInit.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "wraps bare map return in {:ok, ...}" do
    input = """
    defmodule BareInitMap do
      use GenServer

      def start_link do
        GenServer.start_link(__MODULE__, [])
      end

      def init(_opts) do
        %{count: 0}
      end

      def handle_call(:get, _from, state) do
        {:reply, state.count, state}
      end
    end
    """

    expected = """
    defmodule BareInitMap do
      use GenServer

      def start_link do
        GenServer.start_link(__MODULE__, [])
      end

      def init(_opts) do
        {:ok, %{count: 0}}
      end

      def handle_call(:get, _from, state) do
        {:reply, state.count, state}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "wraps bare struct return in {:ok, ...}" do
    input = """
    defmodule BareStruct do
      use GenServer

      def init(_opts) do
        %MyStruct{key: :value}
      end
    end
    """

    expected = """
    defmodule BareStruct do
      use GenServer

      def init(_opts) do
        {:ok, %MyStruct{key: :value}}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "wraps bare list return in {:ok, ...}" do
    input = """
    defmodule BareList do
      use GenServer

      def init(_opts) do
        [1, 2, 3]
      end
    end
    """

    expected = """
    defmodule BareList do
      use GenServer

      def init(_opts) do
        {:ok, [1, 2, 3]}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "does not touch {:ok, state}" do
    input = """
    defmodule ValidInit do
      use GenServer

      def init(opts) do
        {:ok, opts}
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not touch {:stop, reason}" do
    input = """
    defmodule StopInit do
      use GenServer

      def init(_opts) do
        {:stop, :normal}
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not touch :ignore" do
    input = """
    defmodule IgnoreInit do
      use GenServer

      def init(_opts) do
        :ignore
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not touch {:ok, state, timeout}" do
    input = """
    defmodule TimeoutInit do
      use GenServer

      def init(opts) do
        {:ok, opts, 5000}
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule BareInit do
      use GenServer

      def init(_opts) do
        %{key: :value}
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanModule do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input), input)
  end
end
