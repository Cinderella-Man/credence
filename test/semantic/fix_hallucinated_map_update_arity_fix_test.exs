defmodule Credence.Semantic.FixHallucinatedMapUpdateArityFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixHallucinatedMapUpdateArity

  @real_message "Map.update/3 is undefined or private. Did you mean:\n\n    * update/4\n"

  defp fix(source, message, line \\ 1) do
    FixHallucinatedMapUpdateArity.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes Map.update/3 by inserting default 0" do
    input = """
    defmodule MapUpdateArityExample do
      def increment_count(map, key) do
        Map.update(map, key, fn val -> val + 1 end)
      end
    end
    """

    expected = """
    defmodule MapUpdateArityExample do
      def increment_count(map, key) do
        Map.update(map, key, 0, fn val -> val + 1 end)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "leaves Map.update/4 unchanged" do
    input = """
    defmodule CleanExample do
      def increment_count(map, key) do
        Map.update(map, key, 0, fn val -> val + 1 end)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), input)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule MapUpdateArityExample do
      def increment_count(map, key) do
        Map.update(map, key, fn val -> val + 1 end)
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message, 3))
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "fixes Map.update/3 with multiline anonymous function" do
    input = """
    defmodule MapUpdateArityExample do
      def add_value(map, key, val) do
        Map.update(map, key, fn existing ->
          existing + val
        end)
      end
    end
    """

    expected = """
    defmodule MapUpdateArityExample do
      def add_value(map, key, val) do
        Map.update(map, key, 0, fn existing ->
          existing + val
        end)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "fixes Map.update/3 with capture syntax" do
    input = """
    defmodule MapUpdateArityExample do
      def increment(map, key) do
        Map.update(map, key, &(&1 + 1))
      end
    end
    """

    expected = """
    defmodule MapUpdateArityExample do
      def increment(map, key) do
        Map.update(map, key, 0, &(&1 + 1))
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end
end
