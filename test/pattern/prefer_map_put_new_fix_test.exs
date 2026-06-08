defmodule Credence.Pattern.PreferMapPutNewFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferMapPutNew

  describe "fix rewrites the if/unless form into Map.put_new" do
    test "standard if-has_key-else-put with surrounding binding" do
      code = """
      def run(map, key, val) do
        new_map =
          if Map.has_key?(map, key) do
            map
          else
            Map.put(map, key, val)
          end

        new_map
      end
      """

      expected = """
      def run(map, key, val) do
        new_map =
          Map.put_new(map, key, val)

        new_map
      end
      """

      assert fix(PreferMapPutNew, code) == expected
    end

    test "inside Enum.reduce" do
      code = """
      def run(list) do
        Enum.reduce(list, %{}, fn {k, v}, acc ->
          if Map.has_key?(acc, k) do
            acc
          else
            Map.put(acc, k, v)
          end
        end)
      end
      """

      expected = """
      def run(list) do
        Enum.reduce(list, %{}, fn {k, v}, acc ->
          Map.put_new(acc, k, v)
        end)
      end
      """

      assert fix(PreferMapPutNew, code) == expected
    end

    test "negated condition with swapped branches" do
      code = """
      def run(map, key, val) do
        if !Map.has_key?(map, key) do
          Map.put(map, key, val)
        else
          map
        end
      end
      """

      expected = """
      def run(map, key, val) do
        Map.put_new(map, key, val)
      end
      """

      assert fix(PreferMapPutNew, code) == expected
    end

    test "unless variant" do
      code = """
      def run(map, key, val) do
        unless Map.has_key?(map, key) do
          Map.put(map, key, val)
        else
          map
        end
      end
      """

      expected = """
      def run(map, key, val) do
        Map.put_new(map, key, val)
      end
      """

      assert fix(PreferMapPutNew, code) == expected
    end

    test "scalar literal value" do
      code = """
      def run(map, key) do
        if Map.has_key?(map, key) do
          map
        else
          Map.put(map, key, 0)
        end
      end
      """

      expected = """
      def run(map, key) do
        Map.put_new(map, key, 0)
      end
      """

      assert fix(PreferMapPutNew, code) == expected
    end
  end

  describe "fix is a no-op on unsafe / non-matching code" do
    test "impure value is left unchanged" do
      code = """
      def run(map, key) do
        if Map.has_key?(map, key) do
          map
        else
          Map.put(map, key, compute_default())
        end
      end
      """

      assert fix(PreferMapPutNew, code) == code
    end

    test "double-negated condition is left unchanged" do
      code = """
      def run(map, key, val) do
        if !!Map.has_key?(map, key) do
          Map.put(map, key, val)
        else
          map
        end
      end
      """

      assert fix(PreferMapPutNew, code) == code
    end

    test "unless with negated condition is left unchanged" do
      code = """
      def run(map, key, val) do
        unless !Map.has_key?(map, key) do
          Map.put(map, key, val)
        else
          map
        end
      end
      """

      assert fix(PreferMapPutNew, code) == code
    end

    test "already Map.put_new is left unchanged" do
      code = """
      def run(map, key, val) do
        Map.put_new(map, key, val)
      end
      """

      assert fix(PreferMapPutNew, code) == code
    end
  end
end
