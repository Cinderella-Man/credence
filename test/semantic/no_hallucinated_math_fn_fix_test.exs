defmodule Credence.Semantic.NoHallucinatedMathFnFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedMathFn

  @min_message ":math.min/2 is undefined or private. Did you mean:\n\n    * sin/1\n"
  @max_message ":math.max/2 is undefined or private"

  defp fix(source, message, line \\ 1) do
    NoHallucinatedMathFn.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "replaces :math.min with Kernel.min" do
    input = """
    defmodule SharedPoolBucket do
      use GenServer

      @impl true
      def init(state) do
        {:ok, state}
      end

      @impl true
      def handle_call({:refill, old_tokens, elapsed_ms, refill_rate, capacity}, _from, state) do
        new_tokens = :math.min(capacity, old_tokens + elapsed_ms * refill_rate / 1000)
        {:reply, new_tokens, state}
      end
    end
    """

    expected = """
    defmodule SharedPoolBucket do
      use GenServer

      @impl true
      def init(state) do
        {:ok, state}
      end

      @impl true
      def handle_call({:refill, old_tokens, elapsed_ms, refill_rate, capacity}, _from, state) do
        new_tokens = Kernel.min(capacity, old_tokens + elapsed_ms * refill_rate / 1000)
        {:reply, new_tokens, state}
      end
    end
    """

    confirm_fix(fix(input, @min_message), expected)
  end

  test "replaces :math.max with Kernel.max" do
    input = """
    defmodule Pool do
      def limit(val, cap) do
        :math.max(0, val - cap)
      end
    end
    """

    expected = """
    defmodule Pool do
      def limit(val, cap) do
        Kernel.max(0, val - cap)
      end
    end
    """

    confirm_fix(fix(input, @max_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule X do
      def f(a, b), do: :math.min(a, b)
    end
    """

    assert valid_syntax?(fix(input, @min_message))
  end

  test "returns source unchanged when no :math.min or :math.max present" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @min_message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def add(a, b), do: a + b
    end
    """

    confirm_fix(fix(input, @min_message), input)
  end
end
