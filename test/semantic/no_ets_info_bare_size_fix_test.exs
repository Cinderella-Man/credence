defmodule Credence.Semantic.NoEtsInfoBareSizeFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoEtsInfoBareSize

  # The real diagnostic Elixir emits for `:ets.info(table, size)`.
  @real_message "undefined variable \"size\""

  defp diag(line, col \\ 37) do
    %{severity: :error, message: @real_message, position: {line, col}}
  end

  describe "fix/2" do
    test "atomises bare size in :ets.info call" do
      source = """
      defmodule LRUCache do
        use GenServer

        def start_link(opts) do
          name = Keyword.fetch!(opts, :name)
          GenServer.start_link(__MODULE__, opts, name: name)
        end

        @impl GenServer
        def init(opts) do
          table = :ets.new(:cache, [:set, :public, :named_table])
          {:ok, %{table: table}}
        end

        def handle_call(:count, _from, %{table: table} = state) do
          current_size = :ets.info(table, size)
          {:reply, current_size, state}
        end
      end
      """

      expected = """
      defmodule LRUCache do
        use GenServer

        def start_link(opts) do
          name = Keyword.fetch!(opts, :name)
          GenServer.start_link(__MODULE__, opts, name: name)
        end

        @impl GenServer
        def init(opts) do
          table = :ets.new(:cache, [:set, :public, :named_table])
          {:ok, %{table: table}}
        end

        def handle_call(:count, _from, %{table: table} = state) do
          current_size = :ets.info(table, :size)
          {:reply, current_size, state}
        end
      end
      """

      confirm_fix(NoEtsInfoBareSize.fix(source, diag(16)), expected)
    end

    test "handles extra whitespace before size" do
      source = ~S"""
      defmodule M do
        def count(tid), do: :ets.info(tid,   size)
      end
      """

      expected = ~S"""
      defmodule M do
        def count(tid), do: :ets.info(tid,   :size)
      end
      """

      confirm_fix(NoEtsInfoBareSize.fix(source, diag(2)), expected)
    end

    test "no-op when size is already an atom" do
      source = ~S"""
      defmodule M do
        def count(tid), do: :ets.info(tid, :size)
      end
      """

      confirm_fix(NoEtsInfoBareSize.fix(source, diag(2)), source)
    end

    test "no-op on a line without :ets.info" do
      source = """
      defmodule M do
        def f(size), do: size + 1
      end
      """

      confirm_fix(NoEtsInfoBareSize.fix(source, diag(2)), source)
    end

    test "returns source unchanged when position is nil" do
      source = ":ets.info(t, size)"
      diag = %{severity: :error, message: @real_message, position: nil}
      confirm_fix(NoEtsInfoBareSize.fix(source, diag), source)
    end
  end

  describe "fix output is well-formed" do
    test "fixed output parses" do
      source = """
      defmodule M do
        def count(tid), do: :ets.info(tid, size)
      end
      """

      assert valid_syntax?(NoEtsInfoBareSize.fix(source, diag(2)))
    end
  end
end
