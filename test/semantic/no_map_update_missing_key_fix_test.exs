defmodule Credence.Semantic.NoMapUpdateMissingKeyFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoMapUpdateMissingKey

  @message "expected a map with key :timer_ref in map update syntax:\n\n    %{state | timer_ref: timer_ref}\n\nbut got type:\n\n    dynamic(%{\n      counter: integer(),\n      data: list()\n    })\n\nwhere \"state\" was given the type:\n\n    # type: dynamic(%{\n      counter: integer(),\n      data: list()\n    })\n    # from: credence_check.ex:4:5\n    state = %{counter: 0, data: []}\n"

  defp fix(source, message, line \\ 1) do
    NoMapUpdateMissingKey.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "adds the missing key to the map literal" do
    input = """
    defmodule Example do
      def setup do
        timer_ref = Process.send_after(self(), :tick, 1000)
        state = %{counter: 0, data: []}
        {:ok, %{state | timer_ref: timer_ref}}
      end
    end
    """

    expected = """
    defmodule Example do
      def setup do
        timer_ref = Process.send_after(self(), :tick, 1000)
        state = %{counter: 0, data: [], timer_ref: nil}
        {:ok, %{state | timer_ref: timer_ref}}
      end
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def setup do
        timer_ref = Process.send_after(self(), :tick, 1000)
        state = %{counter: 0, data: []}
        {:ok, %{state | timer_ref: timer_ref}}
      end
    end
    """

    assert valid_syntax?(fix(input, @message))
  end

  test "returns source unchanged when variable already has the key" do
    input = """
    defmodule Example do
      def setup do
        timer_ref = Process.send_after(self(), :tick, 1000)
        state = %{counter: 0, data: [], timer_ref: nil}
        {:ok, %{state | timer_ref: timer_ref}}
      end
    end
    """

    result = fix(input, @message)
    confirm_fix(result, input)
  end

  test "returns source unchanged when variable is not assigned to a map literal" do
    input = """
    defmodule Example do
      def setup do
        state = build_state()
        {:ok, %{state | timer_ref: nil}}
      end
    end
    """

    result = fix(input, @message)
    confirm_fix(result, input)
  end

  test "adds the key to the literal without mangling a `var = %{var | ...}` update-reassignment" do
    input = """
    defmodule Example do
      def setup do
        state = %{counter: 0, data: []}
        state = %{state | timer_ref: nil}
        state
      end
    end
    """

    expected = """
    defmodule Example do
      def setup do
        state = %{counter: 0, data: [], timer_ref: nil}
        state = %{state | timer_ref: nil}
        state
      end
    end
    """

    confirm_fix(fix(input, @message, 4), expected)
  end

  test "leaves a lone `var = %{var | ...}` update untouched when there is no map literal" do
    input = """
    defmodule Example do
      def bump(state) do
        state = %{state | timer_ref: nil}
        state
      end
    end
    """

    confirm_fix(fix(input, @message, 3), input)
  end

  test "fixes the real-world diagnostic message" do
    real_message = "expected a map with key :timer_ref in map update syntax:\n\n    %{state | timer_ref: timer_ref}\n\nbut got type:\n\n    dynamic(%{\n      cleanup_interval_ms: term(),\n      clock: term(),\n      idempotency: empty_map(),\n      next_id: integer(),\n      payments: empty_map(),\n      processor: term(),\n      ttl_ms: term()\n    })\n\nwhere \"state\" was given the type:\n\n    # type: dynamic(%{\n      cleanup_interval_ms: term(),\n      clock: term(),\n      idempotency: empty_map(),\n      next_id: integer(),\n      payments: empty_map(),\n      processor: term(),\n      ttl_ms: term()\n    })\n    # from: credence_check.ex:40:11\n    state = %{\n      payments: %{},\n      idempotency: %{},\n      next_id: 1,\n      clock: clock,\n      ttl_ms: ttl_ms,\n      cleanup_interval_ms: cleanup_interval_ms,\n      processor: processor\n    }\n\nwhere \"timer_ref\" was given the type:\n\n    # type: dynamic()\n    # from: credence_check.ex:34:15\n    timer_ref =\n      case cleanup_interval_ms do\n        :infinity -> nil\n        _ -> Process.send_after(self(), :cleanup, cleanup_interval_ms)\n      end\n"

    input = """
    defmodule CoalescingPayments do
      def init(opts) do
        cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, :timer.seconds(5))

        timer_ref =
          case cleanup_interval_ms do
            :infinity -> nil
            _ -> Process.send_after(self(), :cleanup, cleanup_interval_ms)
          end

        clock = Keyword.get(opts, :clock, &System.system_time/1)
        ttl_ms = Keyword.get(opts, :ttl_ms, :timer.seconds(30))

        state = %{
          payments: %{},
          idempotency: %{},
          next_id: 1,
          clock: clock,
          ttl_ms: ttl_ms,
          cleanup_interval_ms: cleanup_interval_ms,
          processor: processor
        }

        {:ok, %{state | timer_ref: timer_ref}}
      end
    end
    """

    expected = """
    defmodule CoalescingPayments do
      def init(opts) do
        cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, :timer.seconds(5))

        timer_ref =
          case cleanup_interval_ms do
            :infinity -> nil
            _ -> Process.send_after(self(), :cleanup, cleanup_interval_ms)
          end

        clock = Keyword.get(opts, :clock, &System.system_time/1)
        ttl_ms = Keyword.get(opts, :ttl_ms, :timer.seconds(30))

        state = %{
          payments: %{},
          idempotency: %{},
          next_id: 1,
          clock: clock,
          ttl_ms: ttl_ms,
          cleanup_interval_ms: cleanup_interval_ms,
          processor: processor,
          timer_ref: nil
        }

        {:ok, %{state | timer_ref: timer_ref}}
      end
    end
    """

    confirm_fix(fix(input, real_message, 50), expected)
  end
end
