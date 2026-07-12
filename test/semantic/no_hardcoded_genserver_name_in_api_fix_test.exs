defmodule Credence.Semantic.NoHardcodedGenserverNameInApiFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHardcodedGenserverNameInApi

  # The real diagnostic Elixir emits when a case clause uses :catch.
  @real_message "unexpected option :catch in \"case\""

  defp fix(source, line \\ 1) do
    NoHardcodedGenserverNameInApi.fix(source, %{
      severity: :error,
      message: @real_message,
      position: {line, 1}
    })
  end

  describe "fix/2" do
    test "replaces __MODULE__ in GenServer.call with server()" do
      input = ~S"""
      defmodule FeatureFlags do
        use GenServer

        def enable(flag), do: GenServer.call(__MODULE__, {:write, flag, :on})

        @impl true
        def init(state) do
          {:ok, state}
        end
      end
      """

      expected = ~S"""
      defmodule FeatureFlags do
        use GenServer

        @pt_server {__MODULE__, :server}
        @pt_table {__MODULE__, :table}
        @pt_hist {__MODULE__, :hist}

        defp server, do: :persistent_term.get(@pt_server)
        defp table, do: :persistent_term.get(@pt_table)
        defp hist, do: :persistent_term.get(@pt_hist)
        def enable(flag), do: GenServer.call(server(), {:write, flag, :on})

        @impl true
        def init(state) do
          :persistent_term.put(@pt_server, self())
          :persistent_term.put(@pt_table, state.table_name)
          :persistent_term.put(@pt_hist, state.hist_name)
          {:ok, state}
        end
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "replaces literal ETS table atoms with helpers" do
      input = ~S"""
      defmodule FeatureFlags do
        use GenServer

        def enabled?(flag) do
          case :ets.lookup(:feature_flags, flag) do
            [{^flag, state, _}] -> state == :on
            [] -> false
          end
        end

        @impl true
        def init(state) do
          {:ok, state}
        end
      end
      """

      expected = ~S"""
      defmodule FeatureFlags do
        use GenServer

        @pt_server {__MODULE__, :server}
        @pt_table {__MODULE__, :table}
        @pt_hist {__MODULE__, :hist}

        defp server, do: :persistent_term.get(@pt_server)
        defp table, do: :persistent_term.get(@pt_table)
        defp hist, do: :persistent_term.get(@pt_hist)

        def enabled?(flag) do
          case :ets.lookup(table(), flag) do
            [{^flag, state, _}] -> state == :on
            [] -> false
          end
        end

        @impl true
        def init(state) do
          :persistent_term.put(@pt_server, self())
          :persistent_term.put(@pt_table, state.table_name)
          :persistent_term.put(@pt_hist, state.hist_name)
          {:ok, state}
        end
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "preserves __MODULE__ in GenServer.start_link" do
      input = ~S"""
      defmodule FeatureFlags do
        use GenServer

        def start_link(opts \\ []) do
          GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
        end

        @impl true
        def init(state) do
          {:ok, state}
        end
      end
      """

      expected = ~S"""
      defmodule FeatureFlags do
        use GenServer

        @pt_server {__MODULE__, :server}
        @pt_table {__MODULE__, :table}
        @pt_hist {__MODULE__, :hist}

        defp server, do: :persistent_term.get(@pt_server)
        defp table, do: :persistent_term.get(@pt_table)
        defp hist, do: :persistent_term.get(@pt_hist)

        def start_link(opts \\ []) do
          GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
        end

        @impl true
        def init(state) do
          :persistent_term.put(@pt_server, self())
          :persistent_term.put(@pt_table, state.table_name)
          :persistent_term.put(@pt_hist, state.hist_name)
          {:ok, state}
        end
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "no-op when no GenServer.call or ETS lookup present" do
      source = ~S"""
      defmodule NoMatch do
        def hello, do: :world
      end
      """

      confirm_fix(fix(source), source)
    end
  end

  describe "fix output is well-formed" do
    test "fixed output parses" do
      input = ~S"""
      defmodule FeatureFlags do
        use GenServer

        def enable(flag), do: GenServer.call(__MODULE__, {:write, flag, :on})

        def enabled?(flag) do
          case :ets.lookup(:feature_flags, flag) do
            [{^flag, state, _}] -> state == :on
            [] -> false
          end
        end

        @impl true
        def init(state) do
          {:ok, state}
        end
      end
      """

      assert valid_syntax?(fix(input))
    end
  end
end
