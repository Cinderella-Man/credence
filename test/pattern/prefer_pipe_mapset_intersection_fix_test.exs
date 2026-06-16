defmodule Credence.Pattern.PreferPipeMapsetIntersectionFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferPipeMapsetIntersection

  test "rewrites three MapSet.new assignments with nested intersection" do
    input = """
    defmodule Example do
      def get_common(a, b, c) do
        set_a = MapSet.new(a)
        set_b = MapSet.new(b)
        set_c = MapSet.new(c)

        MapSet.intersection(set_a, MapSet.intersection(set_b, set_c))
        |> MapSet.to_list()
      end
    end
    """

    expected = """
    defmodule Example do
      def get_common(a, b, c) do
        a
        |> MapSet.new()
        |> MapSet.intersection(MapSet.new(b))
        |> MapSet.intersection(MapSet.new(c))
        |> MapSet.to_list()
      end
    end
    """

    confirm_fix(fix(PreferPipeMapsetIntersection, input), expected)
  end

  test "rewrites two MapSet.new assignments with intersection" do
    input = """
    defmodule Example do
      def get_common(a, b) do
        set_a = MapSet.new(a)
        set_b = MapSet.new(b)

        MapSet.intersection(set_a, set_b) |> MapSet.to_list()
      end
    end
    """

    expected = """
    defmodule Example do
      def get_common(a, b) do
        a |> MapSet.new() |> MapSet.intersection(MapSet.new(b)) |> MapSet.to_list()
      end
    end
    """

    confirm_fix(fix(PreferPipeMapsetIntersection, input), expected)
  end

  describe "no-op" do
    test "leaves a block with an unused MapSet.new assignment alone" do
      # set_c is assigned but not consumed by the intersection chain; the chain
      # vars are not a permutation of the assignments, so the rule does not fire
      # (rewriting would drop set_c and leave dangling set_a/set_b references).
      code = """
      defmodule Example do
        def get_common(a, b, c) do
          set_a = MapSet.new(a)
          set_b = MapSet.new(b)
          set_c = MapSet.new(c)

          MapSet.intersection(set_a, set_b) |> MapSet.to_list()
        end
      end
      """

      confirm_fix(fix(PreferPipeMapsetIntersection, code), code)
    end

    test "leaves the idiomatic pipeline form alone" do
      code = """
      defmodule Example do
        def get_common(a, b, c) do
          a
          |> MapSet.new()
          |> MapSet.intersection(MapSet.new(b))
          |> MapSet.intersection(MapSet.new(c))
          |> MapSet.to_list()
        end
      end
      """

      confirm_fix(fix(PreferPipeMapsetIntersection, code), code)
    end

    test "leaves code without MapSet.new assignments alone" do
      code = """
      MapSet.intersection(set_a, set_b)
      |> MapSet.to_list()
      """

      confirm_fix(fix(PreferPipeMapsetIntersection, code), code)
    end
  end

  describe "fix round-trip produces no issues" do
    test "three-variable case" do
      fixed =
        fix(PreferPipeMapsetIntersection, """
        defmodule Example do
          def get_common(a, b, c) do
            set_a = MapSet.new(a)
            set_b = MapSet.new(b)
            set_c = MapSet.new(c)

            MapSet.intersection(set_a, MapSet.intersection(set_b, set_c))
            |> MapSet.to_list()
          end
        end
        """)

      assert clean?(PreferPipeMapsetIntersection, fixed)
    end
  end
end
