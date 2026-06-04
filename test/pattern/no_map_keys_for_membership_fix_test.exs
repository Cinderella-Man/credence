defmodule Credence.Pattern.NoMapKeysForMembershipFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoMapKeysForMembership

  defp apply_fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoMapKeysForMembership, code)
  end

  test "x not in Map.keys(m) → not Map.has_key?(m, x) inside a capture" do
    code = """
    defmodule TestMod do
      def filter_visited(queue, visited) do
        Enum.filter(queue, &(&1 not in Map.keys(visited)))
      end
    end
    """

    expected = """
    defmodule TestMod do
      def filter_visited(queue, visited) do
        Enum.filter(queue, &(not Map.has_key?(visited, &1)))
      end
    end
    """

    assert apply_fix(code) == expected
  end

  test "x in Map.keys(m) → Map.has_key?(m, x) inside an if" do
    code = """
    defmodule TestMod do
      def lookup(key, map) do
        if key in Map.keys(map), do: present, else: absent
      end
    end
    """

    expected = """
    defmodule TestMod do
      def lookup(key, map) do
        if Map.has_key?(map, key), do: present, else: absent
      end
    end
    """

    assert apply_fix(code) == expected
  end

  test "no-op when left operand is side-effecting (function call)" do
    code = """
    defmodule TestMod do
      def known?(map) do
        compute_key(map) in Map.keys(map)
      end
    end
    """

    assert apply_fix(code) == code
  end
end
