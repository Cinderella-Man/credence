defmodule Credence.Pattern.NoRedundantDedupBeforeMapsetFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoRedundantDedupBeforeMapset

  test "Enum.dedup(x) |> MapSet.new() -> MapSet.new(x)" do
    code = """
    Enum.dedup(items) |> MapSet.new()
    """

    expected = """
    MapSet.new(items)
    """

    assert fix(NoRedundantDedupBeforeMapset, code) == expected
  end

  test "x |> Enum.dedup() |> MapSet.new() -> MapSet.new(x)" do
    code = """
    items |> Enum.dedup() |> MapSet.new()
    """

    expected = """
    MapSet.new(items)
    """

    assert fix(NoRedundantDedupBeforeMapset, code) == expected
  end

  test "MapSet.new(Enum.dedup(x)) -> MapSet.new(x)" do
    code = """
    MapSet.new(Enum.dedup(items))
    """

    expected = """
    MapSet.new(items)
    """

    assert fix(NoRedundantDedupBeforeMapset, code) == expected
  end

  test "Enum.uniq(x) |> MapSet.new() -> MapSet.new(x)" do
    code = """
    Enum.uniq(items) |> MapSet.new()
    """

    expected = """
    MapSet.new(items)
    """

    assert fix(NoRedundantDedupBeforeMapset, code) == expected
  end

  test "MapSet.new(Enum.uniq(x)) -> MapSet.new(x)" do
    code = """
    MapSet.new(Enum.uniq(items))
    """

    expected = """
    MapSet.new(items)
    """

    assert fix(NoRedundantDedupBeforeMapset, code) == expected
  end

  test "preserves surrounding code, fixes multiple occurrences" do
    code = """
    defmodule Solution do
      def run(first_list, second_list) do
        first_set = Enum.dedup(first_list) |> MapSet.new()
        second_set = Enum.dedup(second_list) |> MapSet.new()
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

    assert fix(NoRedundantDedupBeforeMapset, code) == expected
  end

  test "fixed code produces no further issues" do
    code = """
    defmodule RoundTrip do
      def run(items) do
        Enum.dedup(items) |> MapSet.new()
      end
    end
    """

    fixed = fix(NoRedundantDedupBeforeMapset, code)
    assert clean?(NoRedundantDedupBeforeMapset, fixed)
  end

  # No-op: the sort/sort_by intermediate cases are left untouched.
  test "Enum.uniq(x) |> Enum.sort() |> MapSet.new() is left alone" do
    code = """
    Enum.uniq(items) |> Enum.sort() |> MapSet.new()
    """

    assert fix(NoRedundantDedupBeforeMapset, code) == code
  end

  test "items |> Enum.dedup() |> Enum.sort_by(& &1) |> MapSet.new() is left alone" do
    code = """
    items |> Enum.dedup() |> Enum.sort_by(& &1) |> MapSet.new()
    """

    assert fix(NoRedundantDedupBeforeMapset, code) == code
  end
end
