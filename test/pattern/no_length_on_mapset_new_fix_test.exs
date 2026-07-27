defmodule Credence.Pattern.NoLengthOnMapsetNewFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoLengthOnMapsetNew

  describe "rewrites the anti-pattern" do
    test "length(MapSet.new(arg)) → MapSet.size(MapSet.new(arg))" do
      input = """
      defmodule Bad do
        def count_vertices(vertices) do
          length(MapSet.new(vertices))
        end
      end
      """

      expected = """
      defmodule Bad do
        def count_vertices(vertices) do
          MapSet.size(MapSet.new(vertices))
        end
      end
      """

      confirm_fix(fix(NoLengthOnMapsetNew, input), expected)
    end

    test "length(MapSet.new(literal_list))" do
      input = """
      defmodule Bad do
        def f do
          length(MapSet.new([1, 2, 3]))
        end
      end
      """

      expected = """
      defmodule Bad do
        def f do
          MapSet.size(MapSet.new([1, 2, 3]))
        end
      end
      """

      confirm_fix(fix(NoLengthOnMapsetNew, input), expected)
    end

    test "nested in a larger expression" do
      input = """
      defmodule Bad do
        def f(items) do
          length(MapSet.new(items)) + 1
        end
      end
      """

      expected = """
      defmodule Bad do
        def f(items) do
          MapSet.size(MapSet.new(items)) + 1
        end
      end
      """

      confirm_fix(fix(NoLengthOnMapsetNew, input), expected)
    end
  end

  describe "no-ops outside the safe core" do
    test "MapSet.size(MapSet.new(arg)) — already correct" do
      code = """
      defmodule Good do
        def count_vertices(vertices) do
          MapSet.size(MapSet.new(vertices))
        end
      end
      """

      confirm_fix(fix(NoLengthOnMapsetNew, code), code)
    end

    test "length on a plain variable" do
      code = """
      defmodule Good do
        def count(list) do
          length(list)
        end
      end
      """

      confirm_fix(fix(NoLengthOnMapsetNew, code), code)
    end
  end

  describe "round-trip" do
    test "fixed code raises no further issues" do
      code = """
      defmodule Bad do
        def count_vertices(vertices) do
          length(MapSet.new(vertices))
        end
      end
      """

      assert check(NoLengthOnMapsetNew, fix(NoLengthOnMapsetNew, code)) == []
    end

    test "fixed code is valid Elixir" do
      code = """
      defmodule Bad do
        def count_vertices(vertices) do
          length(MapSet.new(vertices))
        end
      end
      """

      assert valid_syntax?(fix(NoLengthOnMapsetNew, code))
    end
  end
end
