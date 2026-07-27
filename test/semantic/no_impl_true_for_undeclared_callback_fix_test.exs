defmodule Credence.Semantic.NoImplTrueForUndeclaredCallbackFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoImplTrueForUndeclaredCallback

  defp fix(source, message, line) do
    NoImplTrueForUndeclaredCallback.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  defp impl_msg(fun, arity) do
    "got \"@impl true\" for function #{fun}/#{arity} but no behaviour specifies such callback. The known callbacks are:\n\n  * Supervisor.init/1 (function)\n"
  end

  @input """
  defmodule MisusedImpl do
    use Supervisor

    def start_link(opts), do: Supervisor.start_link(__MODULE__, opts)

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def handle_call(:ping, _from, state), do: {:reply, :pong, state}

    @impl true
    def handle_info(_msg, state), do: {:noreply, state}
  end
  """

  test "removes @impl true from undeclared handle_call/3" do
    expected = """
    defmodule MisusedImpl do
      use Supervisor

      def start_link(opts), do: Supervisor.start_link(__MODULE__, opts)

      @impl true
      def init(opts), do: {:ok, opts}

      def handle_call(:ping, _from, state), do: {:reply, :pong, state}

      @impl true
      def handle_info(_msg, state), do: {:noreply, state}
    end
    """

    confirm_fix(fix(@input, impl_msg("handle_call", 3), 10), expected)
  end

  test "removes @impl true from undeclared handle_info/2" do
    expected = """
    defmodule MisusedImpl do
      use Supervisor

      def start_link(opts), do: Supervisor.start_link(__MODULE__, opts)

      @impl true
      def init(opts), do: {:ok, opts}

      @impl true
      def handle_call(:ping, _from, state), do: {:reply, :pong, state}

      def handle_info(_msg, state), do: {:noreply, state}
    end
    """

    confirm_fix(fix(@input, impl_msg("handle_info", 2), 13), expected)
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix(@input, impl_msg("handle_call", 3), 10))
  end

  test "returns source unchanged when line does not point to a def" do
    result = fix(@input, impl_msg("handle_call", 3), 99)
    confirm_fix(result, @input)
  end

  test "returns source unchanged when message does not match pattern" do
    result = fix(@input, "something unrelated", 10)
    confirm_fix(result, @input)
  end
end
