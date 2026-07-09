defmodule Credence.Semantic.FixHallucinatedMapPutArityFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixHallucinatedMapPutArity

  @real_message "Map.put/5 is undefined or private. Did you mean:\n\n    * put/3\n"

  defp fix(source, message, line \\ 1) do
    FixHallucinatedMapPutArity.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes Map.put/5 by chaining into nested Map.put/3 calls" do
    input = """
    defmodule HallucinatedMapPut do
      def build do
        Map.put(%{}, :type, :missing_required, :path, [:a])
      end
    end
    """

    expected = """
    defmodule HallucinatedMapPut do
      def build do
        Map.put(Map.put(%{}, :type, :missing_required), :path, [:a])
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "fixes Map.put/7 by chaining into three nested Map.put/3 calls" do
    input = """
    defmodule HallucinatedMapPut do
      def build do
        Map.put(%{}, :a, 1, :b, 2, :c, 3)
      end
    end
    """

    expected = """
    defmodule HallucinatedMapPut do
      def build do
        Map.put(Map.put(Map.put(%{}, :a, 1), :b, 2), :c, 3)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "leaves Map.put/3 unchanged" do
    input = """
    defmodule CleanExample do
      def build do
        Map.put(%{}, :key, :value)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), input)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule HallucinatedMapPut do
      def build do
        Map.put(%{}, :type, :missing_required, :path, [:a])
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message, 3))
  end

  test "returns source unchanged when no Map.put/5+ present" do
    input = """
    defmodule CleanExample do
      def build do
        Map.put(%{}, :key, :value)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "fixes Map.put/5 with variable map" do
    input = """
    defmodule HallucinatedMapPut do
      def build(map) do
        Map.put(map, :type, :missing_required, :path, [:a])
      end
    end
    """

    expected = """
    defmodule HallucinatedMapPut do
      def build(map) do
        Map.put(Map.put(map, :type, :missing_required), :path, [:a])
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end
end
