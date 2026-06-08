defmodule Credence.Pattern.NoReduceForMapBuildingCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoReduceForMapBuilding

  describe "check — positive cases" do
    test "detects Enum.reduce building a map with Map.put" do
      code = """
      defmodule Bad do
        def build(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            Map.put(acc, x, String.length(x))
          end)
        end
      end
      """

      [issue] = check(NoReduceForMapBuilding, code)
      assert issue.rule == :no_reduce_for_map_building
      assert issue.message =~ "Map.new/2"
    end

    test "detects piped form" do
      code = """
      defmodule Bad do
        def build(list) do
          list
          |> Enum.reduce(%{}, fn x, acc ->
            Map.put(acc, x, x * 2)
          end)
        end
      end
      """

      [issue] = check(NoReduceForMapBuilding, code)
      assert issue.rule == :no_reduce_for_map_building
    end

    test "detects single-expression block wrapper" do
      code = """
      defmodule Bad do
        def build(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            Map.put(acc, x, String.length(x))
          end)
        end
      end
      """

      [issue] = check(NoReduceForMapBuilding, code)
      assert issue.rule == :no_reduce_for_map_building
    end

    test "detects Enum.reduce building a MapSet with MapSet.put" do
      code = """
      defmodule Bad do
        def build(list) do
          Enum.reduce(list, MapSet.new(), fn x, acc ->
            MapSet.put(acc, x)
          end)
        end
      end
      """

      [issue] = check(NoReduceForMapBuilding, code)
      assert issue.rule == :no_reduce_for_map_building
      assert issue.message =~ "MapSet.new/1"
    end

    test "detects piped MapSet form" do
      code = """
      defmodule Bad do
        def build(list) do
          list
          |> Enum.reduce(MapSet.new(), fn x, acc ->
            MapSet.put(acc, x)
          end)
        end
      end
      """

      [issue] = check(NoReduceForMapBuilding, code)
      assert issue.rule == :no_reduce_for_map_building
      assert issue.message =~ "MapSet.new/1"
    end

    test "detects MapSet with capture syntax" do
      code = """
      defmodule Bad do
        def build(list) do
          Enum.reduce(list, MapSet.new(), &MapSet.put(&2, &1))
        end
      end
      """

      [issue] = check(NoReduceForMapBuilding, code)
      assert issue.rule == :no_reduce_for_map_building
      assert issue.message =~ "MapSet.new/1"
    end

    test "detects piped MapSet with capture syntax" do
      code = """
      defmodule Bad do
        def build(list) do
          list
          |> Enum.reduce(MapSet.new(), &MapSet.put(&2, &1))
        end
      end
      """

      [issue] = check(NoReduceForMapBuilding, code)
      assert issue.rule == :no_reduce_for_map_building
      assert issue.message =~ "MapSet.new/1"
    end
  end

  describe "check — negative cases" do
    test "does not flag Enum.reduce with non-empty initial map" do
      code = """
      defmodule Good do
        def build(list, existing) do
          Enum.reduce(list, existing, fn x, acc ->
            Map.put(acc, x, String.length(x))
          end)
        end
      end
      """

      assert check(NoReduceForMapBuilding, code) == []
    end

    test "does not flag when value references acc" do
      code = """
      defmodule Good do
        def count_chars(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            Map.put(acc, x, Map.get(acc, :default, 0) + 1)
          end)
        end
      end
      """

      assert check(NoReduceForMapBuilding, code) == []
    end

    test "does not flag when key references acc" do
      code = """
      defmodule Good do
        def build(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            Map.put(acc, map_size(acc), x)
          end)
        end
      end
      """

      assert check(NoReduceForMapBuilding, code) == []
    end

    test "does not flag when body has multiple statements" do
      code = """
      defmodule Good do
        def build(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            key = String.to_atom(x)
            Map.put(acc, key, String.length(x))
          end)
        end
      end
      """

      assert check(NoReduceForMapBuilding, code) == []
    end

    test "does not flag Enum.reduce with sum accumulation" do
      code = """
      defmodule Good do
        def sum(list) do
          Enum.reduce(list, 0, fn x, acc -> acc + x end)
        end
      end
      """

      assert check(NoReduceForMapBuilding, code) == []
    end

    test "does not flag Map.new (already idiomatic)" do
      code = """
      defmodule Good do
        def build(list) do
          Map.new(list, fn x -> {x, String.length(x)} end)
        end
      end
      """

      assert check(NoReduceForMapBuilding, code) == []
    end

    test "does not flag Enum.into" do
      code = """
      defmodule Good do
        def build(list) do
          Enum.into(list, %{}, fn x -> {x, String.length(x)} end)
        end
      end
      """

      assert check(NoReduceForMapBuilding, code) == []
    end

    test "does not flag MapSet.new (already idiomatic)" do
      code = """
      defmodule Good do
        def build(list) do
          MapSet.new(list)
        end
      end
      """

      assert check(NoReduceForMapBuilding, code) == []
    end

    test "does not flag non-empty MapSet initial" do
      code = """
      defmodule Good do
        def build(list, existing) do
          Enum.reduce(list, existing, fn x, acc ->
            MapSet.put(acc, x)
          end)
        end
      end
      """

      assert check(NoReduceForMapBuilding, code) == []
    end

    test "does not flag MapSet.put when value references acc" do
      code = """
      defmodule Good do
        def build(list) do
          Enum.reduce(list, MapSet.new(), fn x, acc ->
            MapSet.put(acc, hd(acc))
          end)
        end
      end
      """

      assert check(NoReduceForMapBuilding, code) == []
    end

    test "does not flag MapSet.put when value is not the element" do
      code = """
      defmodule Good do
        def build(list) do
          Enum.reduce(list, MapSet.new(), fn x, acc ->
            MapSet.put(acc, x * 2)
          end)
        end
      end
      """

      assert check(NoReduceForMapBuilding, code) == []
    end

    test "does not flag Map.put with MapSet initial" do
      code = """
      defmodule Good do
        def build(list) do
          Enum.reduce(list, MapSet.new(), fn x, acc ->
            Map.put(acc, x, x)
          end)
        end
      end
      """

      assert check(NoReduceForMapBuilding, code) == []
    end

    # `Enum.reduce/2` over a literal `%{}` is *not* the same shape: its first
    # element seeds the accumulator and it raises on an empty enumerable. The
    # fix correctly leaves it alone, so check must not flag it (check/fix
    # agreement).
    test "does not flag bare Enum.reduce/2 over an empty-map literal" do
      code = """
      defmodule Good do
        def build do
          Enum.reduce(%{}, fn x, acc ->
            Map.put(acc, x, x)
          end)
        end
      end
      """

      assert check(NoReduceForMapBuilding, code) == []
    end

    test "does not flag bare Enum.reduce/2 over an empty MapSet literal" do
      code = """
      defmodule Good do
        def build do
          Enum.reduce(MapSet.new(), fn x, acc ->
            MapSet.put(acc, x)
          end)
        end
      end
      """

      assert check(NoReduceForMapBuilding, code) == []
    end
  end
end
