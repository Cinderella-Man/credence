defmodule Credence.Semantic.FixTaskIdFieldAccessFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixTaskIdFieldAccess

  @real_message "unknown key .id in expression:\n\n    task.id\n\nthe given type does not have the given key"

  defp fix(source, message, line \\ 1) do
    FixTaskIdFieldAccess.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "replaces task.id with task.ref" do
    input = """
    defmodule TaskIdField do
      def get_ref do
        task = Task.async(fn -> 42 end)
        task.id
      end
    end
    """

    expected = """
    defmodule TaskIdField do
      def get_ref do
        task = Task.async(fn -> 42 end)
        task.ref
      end
    end
    """

    confirm_fix(fix(input, @real_message, 4), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule TaskIdField do
      def get_ref do
        task = Task.async(fn -> 42 end)
        task.id
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message, 4))
  end

  test "returns source unchanged when no .id present" do
    input = """
    defmodule TaskIdField do
      def get_ref do
        task = Task.async(fn -> 42 end)
        task.ref
      end
    end
    """

    confirm_fix(fix(input, @real_message, 4), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message, 1), input)
  end
end
