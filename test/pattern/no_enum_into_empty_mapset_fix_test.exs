defmodule Credence.Pattern.NoEnumIntoEmptyMapsetFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoEnumIntoEmptyMapset

  test "rewrites Enum.into(enum, MapSet.new()) to MapSet.new(enum)" do
    code = """
    Enum.into(list, MapSet.new())
    """

    expected = """
    MapSet.new(list)
    """

    assert fix(NoEnumIntoEmptyMapset, code) == expected
  end

  test "rewrites Enum.into(enum, MapSet.new(), fun) to MapSet.new(enum, fun)" do
    code = """
    Enum.into(list, MapSet.new(), fn x -> x * 2 end)
    """

    expected = """
    MapSet.new(list, fn x -> x * 2 end)
    """

    assert fix(NoEnumIntoEmptyMapset, code) == expected
  end

  test "rewrites piped Enum.into(MapSet.new()) to MapSet.new(enum)" do
    code = """
    pairs |> Enum.into(MapSet.new())
    """

    expected = """
    MapSet.new(pairs)
    """

    assert fix(NoEnumIntoEmptyMapset, code) == expected
  end

  test "rewrites piped Enum.into(MapSet.new(), fun) to piped MapSet.new(fun)" do
    code = """
    list |> Enum.into(MapSet.new(), fn x -> x * 2 end)
    """

    expected = """
    list |> MapSet.new(fn x -> x * 2 end)
    """

    assert fix(NoEnumIntoEmptyMapset, code) == expected
  end

  test "rewrites Enum.into in a longer pipeline" do
    code = """
    routes
    |> Stream.with_index()
    |> Enum.into(MapSet.new(), fn {r, i} -> {i, r} end)
    """

    expected = """
    routes
    |> Stream.with_index()
    |> MapSet.new(fn {r, i} -> {i, r} end)
    """

    assert fix(NoEnumIntoEmptyMapset, code) == expected
  end

  test "preserves surrounding code" do
    code = """
    defmodule M do
      def build(data) do
        set = Enum.into(data, MapSet.new())
        MapSet.size(set)
      end
    end
    """

    expected = """
    defmodule M do
      def build(data) do
        set = MapSet.new(data)
        MapSet.size(set)
      end
    end
    """

    assert fix(NoEnumIntoEmptyMapset, code) == expected
  end

  # ── No-op cases (check does not fire → fix leaves code unchanged) ──

  test "leaves Enum.into with a variable target untouched" do
    code = """
    Enum.into(list, existing_set)
    """

    assert fix(NoEnumIntoEmptyMapset, code) == code
  end

  test "leaves MapSet.new/1 untouched" do
    code = """
    MapSet.new(list)
    """

    assert fix(NoEnumIntoEmptyMapset, code) == code
  end

  test "leaves Enum.into with an empty map literal untouched" do
    code = """
    Enum.into(list, %{})
    """

    assert fix(NoEnumIntoEmptyMapset, code) == code
  end
end
