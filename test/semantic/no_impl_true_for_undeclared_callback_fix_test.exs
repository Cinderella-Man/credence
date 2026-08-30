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

  test "removes @impl true from the affected module in a multi-module file" do
    input = """
    defmodule UnaffectedNITFUC do
      def ok, do: :ok
    end

    defmodule AffectedNITFUC do
      use Supervisor

      @impl true
      def run, do: :ok
    end
    """

    expected = """
    defmodule UnaffectedNITFUC do
      def ok, do: :ok
    end

    defmodule AffectedNITFUC do
      use Supervisor

      def run, do: :ok
    end
    """

    {result, trace} = Credence.Semantic.fix_with_trace(input)
    assert trace == [{NoImplTrueForUndeclaredCallback, 1}]
    confirm_fix(result, expected)
  end

  test "removes @impl true from an affected nested module" do
    input = """
    defmodule OuterNITFUC do
      defmodule InnerNITFUC do
        use Supervisor

        @impl true
        def run, do: :ok
      end
    end
    """

    expected = """
    defmodule OuterNITFUC do
      defmodule InnerNITFUC do
        use Supervisor

        def run, do: :ok
      end
    end
    """

    {result, trace} = Credence.Semantic.fix_with_trace(input)
    assert trace == [{NoImplTrueForUndeclaredCallback, 1}]
    confirm_fix(result, expected)
  end

  test "removes @impl true across an intervening function attribute" do
    input = """
    defmodule DocumentedNITFUC do
      use Supervisor

      @impl true
      @doc false
      def run, do: :ok
    end
    """

    expected = """
    defmodule DocumentedNITFUC do
      use Supervisor

      @doc false
      def run, do: :ok
    end
    """

    {result, trace} = Credence.Semantic.fix_with_trace(input)
    assert trace == [{NoImplTrueForUndeclaredCallback, 1}]
    confirm_fix(result, expected)
  end

  test "repairs the compiler diagnostic for a punctuated function name" do
    input = """
    defmodule PunctuatedNITFUC do
      use Supervisor

      @impl true
      def valid?(_value), do: true
    end
    """

    expected = """
    defmodule PunctuatedNITFUC do
      use Supervisor

      def valid?(_value), do: true
    end
    """

    {result, trace} = Credence.Semantic.fix_with_trace(input)
    assert trace == [{NoImplTrueForUndeclaredCallback, 1}]
    confirm_fix(result, expected)
  end

  @with_comments """
  defmodule MisusedImpl do
    @moduledoc "A supervisor."
    use Supervisor

    # start it up
    def start_link(opts), do: Supervisor.start_link(__MODULE__, opts)

    @impl true
    def init(opts), do: {:ok, opts}

    @doc "handle a call"
    @impl true
    def handle_call(:ping, _from, state) do
      # reply pong
      {:reply, :pong, state}
    end
  end
  """

  test "preserves moduledoc, @doc, and comments while stripping only the @impl" do
    expected = """
    defmodule MisusedImpl do
      @moduledoc "A supervisor."
      use Supervisor

      # start it up
      def start_link(opts), do: Supervisor.start_link(__MODULE__, opts)

      @impl true
      def init(opts), do: {:ok, opts}

      @doc "handle a call"
      def handle_call(:ping, _from, state) do
        # reply pong
        {:reply, :pong, state}
      end
    end
    """

    confirm_fix(fix(@with_comments, impl_msg("handle_call", 3), 13), expected)
  end

  # Full pipeline: the compiler raises the real diagnostic, the phase discovers
  # this rule, and it is not shadowed by another semantic rule.
  @e2e """
  defmodule MisusedImpl do
    use Supervisor

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def handle_call(:ping, _from, state), do: {:reply, :pong, state}
  end
  """

  test "resolves the diagnostic through the real semantic pipeline" do
    expected = """
    defmodule MisusedImpl do
      use Supervisor

      @impl true
      def init(opts), do: {:ok, opts}

      def handle_call(:ping, _from, state), do: {:reply, :pong, state}
    end
    """

    {result, trace} = Credence.Semantic.fix_with_trace(@e2e)
    assert trace == [{NoImplTrueForUndeclaredCallback, 1}]
    confirm_fix(result, expected)
  end
end
