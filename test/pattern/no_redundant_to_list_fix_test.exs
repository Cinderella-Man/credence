defmodule Credence.Pattern.NoRedundantToListFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoRedundantToList

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoRedundantToList, code, [])
  end

  test "Enum.to_list(x) |> MapSet.new() → MapSet.new(x)" do
    code = "Enum.to_list(items) |> MapSet.new()"
    assert fix(code) == "MapSet.new(items)"
  end

  test "x |> Enum.to_list() |> MapSet.new() → MapSet.new(x)" do
    code = "items |> Enum.to_list() |> MapSet.new()"
    assert fix(code) == "MapSet.new(items)"
  end

  test "MapSet.new(Enum.to_list(x)) → MapSet.new(x)" do
    code = "MapSet.new(Enum.to_list(items))"
    assert fix(code) == "MapSet.new(items)"
  end

  test "Enum.to_list(x) |> Map.new() → Map.new(x)" do
    code = "Enum.to_list(pairs) |> Map.new()"
    assert fix(code) == "Map.new(pairs)"
  end

  test "non-pipe /2 form keeps the transform arg" do
    code = "MapSet.new(Enum.to_list(items), fn x -> x + 1 end)"
    assert fix(code) == "MapSet.new(items, fn x -> x + 1 end)"
  end

  test "preserves surrounding code" do
    code = """
    defmodule Solution do
      def run(first_list, second_list) do
        first_set = Enum.to_list(first_list) |> MapSet.new()
        second_set = Enum.to_list(second_list) |> MapSet.new()
        {first_set, second_set}
      end
    end
    """

    expected = """
    defmodule Solution do
      def run(first_list, second_list) do
        first_set = MapSet.new(first_list)
        second_set = MapSet.new(second_list)
        {first_set, second_set}
      end
    end
    """

    assert fix(code) == expected
  end

  test "fixed code produces no issues" do
    code = """
    defmodule RoundTrip do
      def run(items) do
        Enum.to_list(items) |> MapSet.new()
      end
    end
    """

    fixed = fix(code)
    fixed_ast = Sourceror.parse_string!(fixed)
    assert NoRedundantToList.check(fixed_ast, []) == []
  end

  # Narrowed-out unsafe case: the rule must NOT touch it (would drop the arg).
  test "pipe /2 form is left unchanged" do
    code = "Enum.to_list(items) |> MapSet.new(fn x -> x + 1 end)"
    assert fix(code) == code
  end
end
