defmodule Credence.Semantic.FixUnmatchableTupleDestructureFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixUnmatchableTupleDestructure

  @real_message "misplaced operator |/2\n\nThe | operator is typically used between brackets to mark the tail of a list:\n\n    [head | tail]\n    [head, middle, ... | tail]\n\nIt is also used to update maps and structs, via the %{map | key: value} notation, and in typespecs, such as @type and @spec, to express the union of two types"

  defp fix(source, message, line \\ 1) do
    FixUnmatchableTupleDestructure.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces {var, _} tuple destructure with simple assignment" do
    input = ~S"""
    defmodule SoftCrud.Documents do
      def handle_call({:create, attrs}, _from, state) do
        {inserted_at, _} = DateTime.to_unix(DateTime.utc_now(), :microsecond)
        doc = %{id: state.next_id, title: attrs.title, inserted_at: inserted_at}
        {:reply, {:ok, doc}, %{state | next_id: state.next_id + 1}}
      end
    end
    """

    expected = ~S"""
    defmodule SoftCrud.Documents do
      def handle_call({:create, attrs}, _from, state) do
        inserted_at = DateTime.to_unix(DateTime.utc_now(), :microsecond)
        doc = %{id: state.next_id, title: attrs.title, inserted_at: inserted_at}
        {:reply, {:ok, doc}, %{state | next_id: state.next_id + 1}}
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "replaces {_, var} tuple destructure with simple assignment" do
    input = ~S"""
    defmodule Example do
      def get_value do
        {_, value} = DateTime.to_unix(DateTime.utc_now(), :microsecond)
        value
      end
    end
    """

    expected = ~S"""
    defmodule Example do
      def get_value do
        value = DateTime.to_unix(DateTime.utc_now(), :microsecond)
        value
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule Example do
      def get_timestamp do
        {inserted_at, _} = DateTime.to_unix(DateTime.utc_now(), :microsecond)
        inserted_at
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message, 3))
  end

  test "returns source unchanged when no tuple destructure present" do
    input = ~S"""
    defmodule Example do
      def get_timestamp do
        inserted_at = DateTime.to_unix(DateTime.utc_now(), :microsecond)
        inserted_at
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), input)
  end

  test "returns source unchanged for unrelated code" do
    input = ~S"""
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
