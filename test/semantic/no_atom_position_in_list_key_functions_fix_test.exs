defmodule Credence.Semantic.NoAtomPositionInListKeyFunctionsFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoAtomPositionInListKeyFunctions

  @real_message "redefining module Clock (current version loaded from _build/test/lib/workspace/ebin/Elixir.Clock.beam)"

  defp fix(source, message, line \\ 1) do
    NoAtomPositionInListKeyFunctions.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces case List.keytake with if Enum.any?/Enum.reject" do
    input = """
    defmodule CancelExample do
      def cancel(timer_ref, timers) do
        case List.keytake(timers, timer_ref, :ref) do
          {_removed, remaining} -> {:ok, remaining}
          nil -> {:error, timers}
        end
      end
    end
    """

    expected = """
    defmodule CancelExample do
      def cancel(timer_ref, timers) do
        if Enum.any?(timers, fn t -> t.ref == timer_ref end) do
          {:ok, Enum.reject(timers, fn t -> t.ref == timer_ref end)}
        else
          {:error, timers}
        end
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "replaces List.keyfind with Enum.find" do
    input = """
    defmodule FindExample do
      def find(timer_ref, timers) do
        List.keyfind(timers, timer_ref, :ref)
      end
    end
    """

    expected = """
    defmodule FindExample do
      def find(timer_ref, timers) do
        Enum.find(timers, fn t -> t.ref == timer_ref end)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "replaces List.keydelete with Enum.reject" do
    input = """
    defmodule DeleteExample do
      def delete(timer_ref, timers) do
        List.keydelete(timers, timer_ref, :ref)
      end
    end
    """

    expected = """
    defmodule DeleteExample do
      def delete(timer_ref, timers) do
        Enum.reject(timers, fn t -> t.ref == timer_ref end)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule CancelExample do
      def cancel(timer_ref, timers) do
        case List.keytake(timers, timer_ref, :ref) do
          {_removed, remaining} -> {:ok, remaining}
          nil -> {:error, timers}
        end
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message, 3))
  end

  test "returns source unchanged when no List.keytake present" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def find_item(items, id) do
        Enum.find(items, fn item -> item.id == id end)
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged when position is integer" do
    input = """
    defmodule GoodExample do
      def find(items, key) do
        List.keyfind(items, key, 0)
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
