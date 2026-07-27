defmodule Credence.Semantic.FixTruncatedSpecialFormFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixTruncatedSpecialForm

  defp fix(source, message, line) do
    FixTruncatedSpecialForm.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  @module_msg "undefined variable \"__MODULE\""
  @env_msg "undefined variable \"__ENV\""

  test "fixes truncated __MODULE in function arguments" do
    input = """
    defmodule TruncatedDunder do
      use GenServer

      def start_link(opts \\\\ []) do
        name = Keyword.get(opts, :name, __MODULE)
        GenServer.start_link(__MODULE, %{}, name: name)
      end

      def init(state), do: {:ok, state}
    end
    """

    expected = """
    defmodule TruncatedDunder do
      use GenServer

      def start_link(opts \\\\ []) do
        name = Keyword.get(opts, :name, __MODULE__)
        GenServer.start_link(__MODULE__, %{}, name: name)
      end

      def init(state), do: {:ok, state}
    end
    """

    confirm_fix(fix(input, @module_msg, 6), expected)
  end

  test "fixes truncated __ENV" do
    input = """
    defmodule EnvTest do
      defmacro get_env, do: __ENV
    end
    """

    expected = """
    defmodule EnvTest do
      defmacro get_env, do: __ENV__
    end
    """

    confirm_fix(fix(input, @env_msg, 2), expected)
  end

  test "leaves already-correct __MODULE__ untouched" do
    input = """
    defmodule Correct do
      def name, do: __MODULE__
    end
    """

    confirm_fix(fix(input, @module_msg, 2), input)
  end

  test "fixes truncated form but preserves already-correct form" do
    input = """
    defmodule Mixed do
      def broken, do: __MODULE
      def correct, do: __MODULE__.hello()
    end
    """

    expected = """
    defmodule Mixed do
      def broken, do: __MODULE__
      def correct, do: __MODULE__.hello()
    end
    """

    confirm_fix(fix(input, @module_msg, 2), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule TruncatedDunder do
      use GenServer

      def start_link(opts \\\\ []) do
        name = Keyword.get(opts, :name, __MODULE)
        GenServer.start_link(__MODULE, %{}, name: name)
      end

      def init(state), do: {:ok, state}
    end
    """

    assert valid_syntax?(fix(input, @module_msg, 6))
  end
end
