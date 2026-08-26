defmodule Credence.Semantic.NoModuleLevelInitFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.RuleHelpers
  alias Credence.Semantic.NoModuleLevelInit

  @real_message "undefined function init/0 (there is no such import)"

  defp fix(source, message \\ @real_message, line \\ 1) do
    NoModuleLevelInit.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  test "replaces bare init() with @on_load :init" do
    input = """
    defmodule Factory do
      def init do
        :ok
      end

      init()
    end
    """

    expected = """
    defmodule Factory do
      @on_load :__credence_on_load__

      def __credence_on_load__ do
        init()
        :ok
      end

      def init do
        :ok
      end

    end
    """

    emitted = fix(input)

    confirm_fix(emitted, expected)
    assert RuleHelpers.compile_and_capture(emitted) == RuleHelpers.compile_and_capture(expected)
  end

  test "handles the spec example" do
    input = """
    defmodule Factory do
      def start do
        case Process.whereis(__MODULE__) do
          nil -> Agent.start_link(fn -> %{counters: %{}, factories: %{}} end, name: __MODULE__)
          _ -> :ok
        end
      end

      def init do
        start()
        register_factory(:user, fn seq_fn, _build_fn, overrides ->
          name = Map.get(overrides, :name, "User \#{seq_fn.(:user_name)}")
          email = Map.get(overrides, :email, "user\#{seq_fn.(:user_email)}@example.com")
          %MyApp.User{name: name, email: email, id: nil}
        end)
      end

      def register_factory(factory_name, factory_fn) do
        Agent.update(__MODULE__, fn %{factories: factories} = state ->
          %{state | factories: Map.put(factories, factory_name, factory_fn)}
        end)
      end

      init()
    end
    """

    expected = """
    defmodule Factory do
      @on_load :__credence_on_load__

      def __credence_on_load__ do
        init()
        :ok
      end

      def start do
        case Process.whereis(__MODULE__) do
          nil -> Agent.start_link(fn -> %{counters: %{}, factories: %{}} end, name: __MODULE__)
          _ -> :ok
        end
      end

      def init do
        start()
        register_factory(:user, fn seq_fn, _build_fn, overrides ->
          name = Map.get(overrides, :name, "User \#{seq_fn.(:user_name)}")
          email = Map.get(overrides, :email, "user\#{seq_fn.(:user_email)}@example.com")
          %MyApp.User{name: name, email: email, id: nil}
        end)
      end

      def register_factory(factory_name, factory_fn) do
        Agent.update(__MODULE__, fn %{factories: factories} = state ->
          %{state | factories: Map.put(factories, factory_name, factory_fn)}
        end)
      end

    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Factory do
      def init do
        :ok
      end

      init()
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "returns source unchanged when no bare init() call" do
    input = """
    defmodule Factory do
      def init do
        :ok
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged when no def init" do
    input = """
    defmodule Factory do
      init()
    end
    """

    confirm_fix(fix(input), input)
  end

  test "removes multiple bare init() calls" do
    input = """
    defmodule Factory do
      def init do
        :ok
      end

      init()
      init()
    end
    """

    expected = """
    defmodule Factory do
      @on_load :__credence_on_load__

      def __credence_on_load__ do
        init()
        :ok
      end

      def init do
        :ok
      end

    end
    """

    confirm_fix(fix(input), expected)
  end

  test "preserves code and comments on the same physical line as init()" do
    input = """
    defmodule SameLineNMLI do
      def init, do: :ok
      init(); @mode :ready
      init() # explanation
    end
    """

    expected = """
    defmodule SameLineNMLI do
      @on_load :__credence_on_load__

      def __credence_on_load__ do
        init()
        :ok
      end

      def init, do: :ok
      @mode :ready
       # explanation
    end
    """

    emitted = fix(input)

    confirm_fix(emitted, expected)
    assert RuleHelpers.compile_and_capture(emitted) == RuleHelpers.compile_and_capture(expected)
  end

  test "on-load wrapper succeeds when init returns a value other than :ok" do
    input = """
    defmodule NonOkInitNMLI do
      def init, do: :not_ok
      init()
    end
    """

    emitted = fix(input)

    load_assertion = """

    unless Code.ensure_loaded?(NonOkInitNMLI), do: raise("module did not load")
    """

    control = """
    defmodule NonOkInitControlNMLI do
      @on_load :load
      def load do
        init()
        :ok
      end
      def init, do: :not_ok
    end

    unless Code.ensure_loaded?(NonOkInitControlNMLI), do: raise("control did not load")
    """

    assert {:ok, []} = RuleHelpers.compile_and_capture(control)
    assert {:ok, []} = RuleHelpers.compile_and_capture(emitted <> load_assertion)
  end

  test "repairs init defined with explicit parentheses" do
    input = """
    defmodule ParenthesizedInitNMLI do
      def init(), do: :ok
      init()
    end
    """

    expected = """
    defmodule ParenthesizedInitNMLI do
      @on_load :__credence_on_load__

      def __credence_on_load__ do
        init()
        :ok
      end

      def init(), do: :ok
    end
    """

    emitted = fix(input)

    confirm_fix(emitted, expected)
    assert {:ok, []} = RuleHelpers.compile_and_capture(expected)
    assert RuleHelpers.compile_and_capture(emitted) == RuleHelpers.compile_and_capture(expected)
  end

  test "leaves nested-module bare init() unchanged (only top-level handled)" do
    input = """
    defmodule Outer do
      defmodule Inner do
        def init do
          :ok
        end

        init()
      end
    end
    """

    confirm_fix(fix(input), input)
  end
end
