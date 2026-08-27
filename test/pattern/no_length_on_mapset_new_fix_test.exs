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

    test "length(MapSet.new()) — arity 0" do
      input = """
      defmodule Bad do
        def f do
          length(MapSet.new())
        end
      end
      """

      expected = """
      defmodule Bad do
        def f do
          MapSet.size(MapSet.new())
        end
      end
      """

      confirm_fix(fix(NoLengthOnMapsetNew, input), expected)
    end

    test "length(MapSet.new(items, fun)) — arity 2 with transform" do
      input = """
      defmodule Bad do
        def f(items) do
          length(MapSet.new(items, fn x -> x * 2 end))
        end
      end
      """

      expected = """
      defmodule Bad do
        def f(items) do
          MapSet.size(MapSet.new(items, fn x -> x * 2 end))
        end
      end
      """

      confirm_fix(fix(NoLengthOnMapsetNew, input), expected)
    end

    test "inside a capture" do
      input = """
      defmodule Bad do
        def f(lists) do
          Enum.map(lists, &length(MapSet.new(&1)))
        end
      end
      """

      expected = """
      defmodule Bad do
        def f(lists) do
          Enum.map(lists, &MapSet.size(MapSet.new(&1)))
        end
      end
      """

      confirm_fix(fix(NoLengthOnMapsetNew, input), expected)
    end

    test "two occurrences both rewritten" do
      input = """
      defmodule Bad do
        def f(a, b) do
          length(MapSet.new(a)) == length(MapSet.new(b))
        end
      end
      """

      expected = """
      defmodule Bad do
        def f(a, b) do
          MapSet.size(MapSet.new(a)) == MapSet.size(MapSet.new(b))
        end
      end
      """

      confirm_fix(fix(NoLengthOnMapsetNew, input), expected)
    end
  end

  describe "no-ops outside the safe core" do
    test "alias shadowing MapSet preserves the valid list-producing call" do
      input = """
      defmodule NoLengthOnMapsetNewAliasShadow do
        defmodule ListFactory do
          def new(items), do: items
        end

        alias ListFactory, as: MapSet

        def count(items), do: length(MapSet.new(items))
      end
      """

      emitted = fix(NoLengthOnMapsetNew, input)

      assert check(NoLengthOnMapsetNew, input) == []
      confirm_fix(emitted, input)
      assert Credence.RuleHelpers.compile_and_capture(input) == {:ok, []}
      assert Credence.RuleHelpers.compile_and_capture(emitted) == {:ok, []}
    end

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

    test "piped form MapSet.new(items) |> length() — different AST shape, skipped" do
      code = """
      defmodule Good do
        def f(items) do
          MapSet.new(items) |> length()
        end
      end
      """

      confirm_fix(fix(NoLengthOnMapsetNew, code), code)
    end

    test "renamed alias MS.new — cannot prove it is MapSet, skipped" do
      code = """
      defmodule Good do
        alias MapSet, as: MS

        def f(items) do
          length(MS.new(items))
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
