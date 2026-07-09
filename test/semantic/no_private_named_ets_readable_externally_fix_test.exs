defmodule Credence.Semantic.NoPrivateNamedEtsReadableExternallyFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoPrivateNamedEtsReadableExternally

  # The real diagnostic Elixir emits for the private-ETS-with-external-read pattern.
  @real_message "incompatible types in binary construction:\n\n    <<String.to_atom(to_string(name))::binary, ...>>\n\ngot type:\n\n    dynamic(atom())\n\nbut expected type:\n\n    binary()\n\nwhere \"name\" was given the type:\n\n    # type: dynamic()\n    # from: credence_check.ex:154:22\n    name\n"

  defp fix(source, line \\ 1) do
    NoPrivateNamedEtsReadableExternally.fix(source, %{
      severity: :warning,
      message: @real_message,
      position: {line, 1}
    })
  end

  describe "fix/2" do
    test "changes :private to :protected in :ets.new options" do
      input = ~S"""
      defmodule WeightedLRUCache do
        use GenServer

        def start_link(opts) do
          name = Keyword.fetch!(opts, :name)
          GenServer.start_link(__MODULE__, name, name: name)
        end

        def get(name, key) do
          table = name_to_table(name)
          case :ets.lookup(table, key) do
            [{^key, {value, _weight, _ts}}] -> {:ok, value}
            [] -> :miss
          end
        end

        @impl true
        def init(name) do
          table_name = name_to_table(name)
          :ets.new(table_name, [:set, :private, :named_table])
          {:ok, %{name: name}}
        end

        @impl true
        def handle_call({:put, key, value}, _from, state) do
          table = name_to_table(state.name)
          :ets.insert(table, {key, value})
          {:reply, :ok, state}
        end

        defp name_to_table(name), do: :"#{name}_data"
      end
      """

      expected = ~S"""
      defmodule WeightedLRUCache do
        use GenServer

        def start_link(opts) do
          name = Keyword.fetch!(opts, :name)
          GenServer.start_link(__MODULE__, name, name: name)
        end

        def get(name, key) do
          table = name_to_table(name)

          case :ets.lookup(table, key) do
            [{^key, {value, _weight, _ts}}] -> {:ok, value}
            [] -> :miss
          end
        end

        @impl true
        def init(name) do
          table_name = name_to_table(name)
          :ets.new(table_name, [:set, :protected, :named_table])
          {:ok, %{name: name}}
        end

        @impl true
        def handle_call({:put, key, value}, _from, state) do
          table = name_to_table(state.name)
          :ets.insert(table, {key, value})
          {:reply, :ok, state}
        end

        defp name_to_table(name), do: :"#{name}_data"
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "changes :private to :protected with different option order" do
      input = ~S"""
      defmodule Cache do
        use GenServer

        @impl true
        def init(name) do
          :ets.new(name, [:named_table, :private, :set])
          {:ok, %{}}
        end
      end
      """

      expected = ~S"""
      defmodule Cache do
        use GenServer

        @impl true
        def init(name) do
          :ets.new(name, [:named_table, :protected, :set])
          {:ok, %{}}
        end
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "no-op when table is already :protected" do
      source = ~S"""
      defmodule Cache do
        use GenServer

        @impl true
        def init(name) do
          :ets.new(name, [:set, :protected, :named_table])
          {:ok, %{}}
        end
      end
      """

      confirm_fix(fix(source), source)
    end

    test "no-op when table is :public" do
      source = ~S"""
      defmodule Cache do
        use GenServer

        @impl true
        def init(name) do
          :ets.new(name, [:set, :public, :named_table])
          {:ok, %{}}
        end
      end
      """

      confirm_fix(fix(source), source)
    end

    test "no-op when no :ets.new call present" do
      source = ~S"""
      defmodule NoEts do
        def hello, do: :world
      end
      """

      confirm_fix(fix(source), source)
    end
  end

  describe "fix output is well-formed" do
    test "fixed output parses" do
      input = ~S"""
      defmodule Cache do
        use GenServer

        @impl true
        def init(name) do
          :ets.new(name, [:set, :private, :named_table])
          {:ok, %{}}
        end
      end
      """

      assert valid_syntax?(fix(input))
    end
  end
end
