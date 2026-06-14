defmodule Credence.Pattern.NoReduceForMapBuildingFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoReduceForMapBuilding

  describe "fix — Map direct form" do
    test "replaces Enum.reduce with Map.new" do
      code = """
      Enum.reduce(list, %{}, fn x, acc ->
        Map.put(acc, x, String.length(x))
      end)
      """

      expected = "Map.new(list, fn x -> {x, String.length(x)} end)"

      confirm_fix(fix(NoReduceForMapBuilding, code), expected)
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def build(list) do
          result =
            Enum.reduce(list, %{}, fn x, acc ->
              Map.put(acc, x, x * 2)
            end)

          Map.size(result)
        end
      end
      """

      expected = """
      defmodule M do
        def build(list) do
          result =
            Map.new(list, fn x -> {x, x * 2} end)

          Map.size(result)
        end
      end
      """

      confirm_fix(fix(NoReduceForMapBuilding, code), expected)
    end
  end

  describe "fix — Map piped form" do
    test "replaces piped Enum.reduce with Map.new (no spurious nil arg)" do
      code = """
      list
      |> Enum.reduce(%{}, fn x, acc ->
        Map.put(acc, x, x * 2)
      end)
      """

      expected = """
      list
      |> Map.new(fn x -> {x, x * 2} end)
      """

      confirm_fix(fix(NoReduceForMapBuilding, code), expected)
    end

    test "preserves pipeline head and tail" do
      code = """
      list
      |> Enum.filter(&valid?/1)
      |> Enum.reduce(%{}, fn x, acc ->
        Map.put(acc, x, transform(x))
      end)
      |> Map.keys()
      """

      expected = """
      list
      |> Enum.filter(&valid?/1)
      |> Map.new(fn x -> {x, transform(x)} end)
      |> Map.keys()
      """

      confirm_fix(fix(NoReduceForMapBuilding, code), expected)
    end
  end

  describe "fix — MapSet direct form" do
    test "replaces Enum.reduce with MapSet.new" do
      code = """
      Enum.reduce(list, MapSet.new(), fn x, acc ->
        MapSet.put(acc, x)
      end)
      """

      expected = "MapSet.new(list)"

      confirm_fix(fix(NoReduceForMapBuilding, code), expected)
    end

    test "replaces capture form with MapSet.new" do
      code = "Enum.reduce(list, MapSet.new(), &MapSet.put(&2, &1))"

      expected = "MapSet.new(list)"

      confirm_fix(fix(NoReduceForMapBuilding, code), expected)
    end
  end

  describe "fix — MapSet piped form" do
    test "replaces piped Enum.reduce with MapSet.new" do
      code = """
      list
      |> Enum.reduce(MapSet.new(), fn x, acc ->
        MapSet.put(acc, x)
      end)
      """

      expected = """
      list
      |> MapSet.new()
      """

      confirm_fix(fix(NoReduceForMapBuilding, code), expected)
    end

    test "replaces piped capture form with MapSet.new" do
      code = """
      list
      |> Enum.reduce(MapSet.new(), &MapSet.put(&2, &1))
      """

      expected = """
      list
      |> MapSet.new()
      """

      confirm_fix(fix(NoReduceForMapBuilding, code), expected)
    end
  end

  describe "fix — no-op cases" do
    test "leaves bare Enum.reduce/2 over %{} untouched" do
      code = """
      Enum.reduce(%{}, fn x, acc ->
        Map.put(acc, x, x)
      end)
      """

      confirm_fix(fix(NoReduceForMapBuilding, code), code)
    end

    test "leaves non-empty-accumulator reduce untouched" do
      code = """
      Enum.reduce(list, existing, fn x, acc ->
        Map.put(acc, x, x)
      end)
      """

      confirm_fix(fix(NoReduceForMapBuilding, code), code)
    end

    test "leaves acc-referencing value untouched" do
      code = """
      Enum.reduce(list, %{}, fn x, acc ->
        Map.put(acc, x, Map.get(acc, :n, 0) + 1)
      end)
      """

      confirm_fix(fix(NoReduceForMapBuilding, code), code)
    end
  end

  describe "fix round-trip — produces no new issues" do
    test "Map direct" do
      code = """
      Enum.reduce(list, %{}, fn x, acc ->
        Map.put(acc, x, String.length(x))
      end)
      """

      assert check(NoReduceForMapBuilding, fix(NoReduceForMapBuilding, code)) == []
    end

    test "Map piped" do
      code = """
      list
      |> Enum.reduce(%{}, fn x, acc ->
        Map.put(acc, x, x * 2)
      end)
      """

      assert check(NoReduceForMapBuilding, fix(NoReduceForMapBuilding, code)) == []
    end

    test "MapSet direct" do
      code = """
      Enum.reduce(list, MapSet.new(), fn x, acc ->
        MapSet.put(acc, x)
      end)
      """

      assert check(NoReduceForMapBuilding, fix(NoReduceForMapBuilding, code)) == []
    end

    test "MapSet capture" do
      code = "Enum.reduce(list, MapSet.new(), &MapSet.put(&2, &1))"

      assert check(NoReduceForMapBuilding, fix(NoReduceForMapBuilding, code)) == []
    end

    test "MapSet piped" do
      code = """
      list
      |> Enum.reduce(MapSet.new(), fn x, acc ->
        MapSet.put(acc, x)
      end)
      """

      assert check(NoReduceForMapBuilding, fix(NoReduceForMapBuilding, code)) == []
    end
  end
end
