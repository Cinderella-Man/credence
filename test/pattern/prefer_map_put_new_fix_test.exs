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

      confirm_fix(fix(PreferMapPutNew, code), expected)
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

      confirm_fix(fix(PreferMapPutNew, code), expected)
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

      confirm_fix(fix(PreferMapPutNew, code), expected)
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

      confirm_fix(fix(PreferMapPutNew, code), expected)
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

      confirm_fix(fix(PreferMapPutNew, code), expected)
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

      confirm_fix(fix(PreferMapPutNew, code), code)
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

      confirm_fix(fix(PreferMapPutNew, code), code)
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

      confirm_fix(fix(PreferMapPutNew, code), code)
    end

    test "already Map.put_new is left unchanged" do
      code = """
      def run(map, key, val) do
        Map.put_new(map, key, val)
      end
      """

      confirm_fix(fix(PreferMapPutNew, code), code)
    end
  end

  # ── An EMBEDDABLE fixture, for `test/dsl_macro_protection_test.exs`. ──
  #
  # This rule declares `unsafe_in_dsl/0`, and that gate proves the declaration
  # actually protects the macro by wrapping a fixture in an `expr(...)` or a
  # `defn` body and requiring the fix to be dropped. It can only wrap a BARE
  # EXPRESSION, and every other fixture in this file is a whole `defmodule` — so
  # without this one the gate has nothing to embed and reports the rule as
  # having vacuous coverage. It pins the ordinary rewrite too, so it is a real
  # test rather than a fixture parked for another file to find.
  describe "embeddable fixture (DSL macro protection)" do
    test "the bare expression form rewrites" do
      input = """
      if Map.has_key?(a, b) do
        a
      else
        Map.put(a, b, c)
      end
      """

      expected = "Map.put_new(a, b, c)"

      confirm_fix(fix(Credence.Pattern.PreferMapPutNew, input), expected)
    end
  end
end
