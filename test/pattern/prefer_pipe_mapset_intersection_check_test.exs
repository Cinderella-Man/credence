defmodule Credence.Pattern.PreferPipeMapsetIntersectionCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferPipeMapsetIntersection

  describe "flags the anti-pattern" do
    test "detects three MapSet.new assignments with nested intersection" do
      code = """
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

      assert flagged?(PreferPipeMapsetIntersection, code)
    end

    test "detects two MapSet.new assignments with intersection" do
      code = """
      defmodule Example do
        def get_common(a, b) do
          set_a = MapSet.new(a)
          set_b = MapSet.new(b)

          MapSet.intersection(set_a, set_b)
          |> MapSet.to_list()
        end
      end
      """

      assert flagged?(PreferPipeMapsetIntersection, code)
    end
  end

  describe "leaves good code alone" do
    test "does not flag the idiomatic pipeline form" do
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

      assert clean?(PreferPipeMapsetIntersection, code)
    end

    test "does not flag code without MapSet.new assignments" do
      code = """
      MapSet.intersection(set_a, set_b)
      |> MapSet.to_list()
      """

      assert clean?(PreferPipeMapsetIntersection, code)
    end

    test "does not flag a single MapSet.new without intersection" do
      code = """
      set_a = MapSet.new(a)
      MapSet.to_list(set_a)
      """

      assert clean?(PreferPipeMapsetIntersection, code)
    end

    test "does not flag when an assignment is left unused by the chain" do
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

      assert clean?(PreferPipeMapsetIntersection, code)
    end

    test "does not flag when the chain orders vars differently than the assignments" do
      code = """
      defmodule Example do
        def get_common(a, b, c) do
          set_a = MapSet.new(a)
          set_b = MapSet.new(b)
          set_c = MapSet.new(c)

          MapSet.intersection(set_b, MapSet.intersection(set_a, set_c)) |> MapSet.to_list()
        end
      end
      """

      assert clean?(PreferPipeMapsetIntersection, code)
    end

    test "does not flag when the chain references a var twice" do
      code = """
      defmodule Example do
        def get_common(a, b) do
          set_a = MapSet.new(a)
          set_b = MapSet.new(b)

          MapSet.intersection(set_a, MapSet.intersection(set_a, set_b)) |> MapSet.to_list()
        end
      end
      """

      assert clean?(PreferPipeMapsetIntersection, code)
    end
  end
end
