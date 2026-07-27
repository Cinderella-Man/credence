defmodule Credence.Pattern.NoLengthOnMapsetNewCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoLengthOnMapsetNew

  describe "flags the anti-pattern" do
    test "length(MapSet.new(arg))" do
      code = """
      defmodule Bad do
        def count_vertices(vertices) do
          length(MapSet.new(vertices))
        end
      end
      """

      [issue] = check(NoLengthOnMapsetNew, code)
      assert issue.rule == :no_length_on_mapset_new
    end

    test "length(MapSet.new(literal_list))" do
      code = """
      defmodule Bad do
        def f do
          length(MapSet.new([1, 2, 3]))
        end
      end
      """

      assert [%{rule: :no_length_on_mapset_new}] = check(NoLengthOnMapsetNew, code)
    end

    test "nested in a larger expression" do
      code = """
      defmodule Bad do
        def f(items) do
          length(MapSet.new(items)) + 1
        end
      end
      """

      assert [%{rule: :no_length_on_mapset_new}] = check(NoLengthOnMapsetNew, code)
    end
  end

  describe "no issue — outside the safe core" do
    test "MapSet.size(MapSet.new(arg)) — already the correct form" do
      code = """
      defmodule Good do
        def count_vertices(vertices) do
          MapSet.size(MapSet.new(vertices))
        end
      end
      """

      assert check(NoLengthOnMapsetNew, code) == []
    end

    test "length on a plain variable" do
      code = """
      defmodule Good do
        def count(list) do
          length(list)
        end
      end
      """

      assert check(NoLengthOnMapsetNew, code) == []
    end

    test "length on a list literal" do
      code = """
      defmodule Good do
        def f do
          length([1, 2, 3])
        end
      end
      """

      assert check(NoLengthOnMapsetNew, code) == []
    end

    test "MapSet.new alone without length" do
      code = """
      defmodule Good do
        def make_set(items) do
          MapSet.new(items)
        end
      end
      """

      assert check(NoLengthOnMapsetNew, code) == []
    end

    test "length on Map.keys — not MapSet" do
      code = """
      defmodule Good do
        def f(map) do
          length(Map.keys(map))
        end
      end
      """

      assert check(NoLengthOnMapsetNew, code) == []
    end
  end
end
