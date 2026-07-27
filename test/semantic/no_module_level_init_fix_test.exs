defmodule Credence.Semantic.NoModuleLevelInitFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

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
      @on_load :init

      def init do
        :ok
      end

    end
    """

    confirm_fix(fix(input), expected)
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
      @on_load :init

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
end
