defmodule Credence.Pattern.NoRedundantToListFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoRedundantToList

  test "Enum.to_list(x) |> MapSet.new() → MapSet.new(x)" do
    code = "Enum.to_list(items) |> MapSet.new()"

    confirm_fix(fix(NoRedundantToList, code), "MapSet.new(items)")
  end

  test "x |> Enum.to_list() |> MapSet.new() → MapSet.new(x)" do
    code = "items |> Enum.to_list() |> MapSet.new()"

    confirm_fix(fix(NoRedundantToList, code), "MapSet.new(items)")
  end

  test "MapSet.new(Enum.to_list(x)) → MapSet.new(x)" do
    code = "MapSet.new(Enum.to_list(items))"

    confirm_fix(fix(NoRedundantToList, code), "MapSet.new(items)")
  end

  test "Enum.to_list(x) |> Map.new() → Map.new(x)" do
    code = "Enum.to_list(pairs) |> Map.new()"

    confirm_fix(fix(NoRedundantToList, code), "Map.new(pairs)")
  end

  test "non-pipe /2 form keeps the transform arg" do
    code = "MapSet.new(Enum.to_list(items), fn x -> x + 1 end)"

    confirm_fix(fix(NoRedundantToList, code), "MapSet.new(items, fn x -> x + 1 end)")
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

    confirm_fix(fix(NoRedundantToList, code), expected)
  end

  test "fixed code produces no issues" do
    code = """
    defmodule RoundTrip do
      def run(items) do
        Enum.to_list(items) |> MapSet.new()
      end
    end
    """

    fixed = fix(NoRedundantToList, code)
    assert clean?(NoRedundantToList, fixed)
  end

  # Narrowed-out unsafe case: the rule must NOT touch it (would drop the arg).
  test "pipe /2 form is left unchanged" do
    code = "Enum.to_list(items) |> MapSet.new(fn x -> x + 1 end)"

    confirm_fix(fix(NoRedundantToList, code), code)
  end
end
