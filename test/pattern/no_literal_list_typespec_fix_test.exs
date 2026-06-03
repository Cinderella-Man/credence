defmodule Credence.Pattern.NoLiteralListTypespecFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoLiteralListTypespec

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoLiteralListTypespec, code, [])
  end

  describe "converts literal list to tuple" do
    test "two elements" do
      assert fix("@spec foo(integer()) :: [pos_integer(), pos_integer()]") ==
               "@spec foo(integer()) :: {pos_integer(), pos_integer()}"
    end

    test "different types" do
      assert fix("@spec foo(integer()) :: [atom(), integer()]") ==
               "@spec foo(integer()) :: {atom(), integer()}"
    end

    test "three elements" do
      assert fix("@spec foo(integer()) :: [atom(), integer(), string()]") ==
               "@spec foo(integer()) :: {atom(), integer(), string()}"
    end

    test "remote type elements" do
      assert fix("@spec foo(integer()) :: [String.t(), atom()]") ==
               "@spec foo(integer()) :: {String.t(), atom()}"
    end

    test "preserves indentation" do
      assert fix("  @spec foo(integer()) :: [pos_integer(), pos_integer()]") ==
               "  @spec foo(integer()) :: {pos_integer(), pos_integer()}"
    end

    test "only the return type changes; the rest is byte-for-byte preserved" do
      code = """
      defmodule Solution do
        @moduledoc "Finds numbers"
        @spec find([pos_integer()]) :: [pos_integer(), pos_integer()]
        def find(numbers) do
          {1, 2}
        end
      end
      """

      expected = """
      defmodule Solution do
        @moduledoc "Finds numbers"
        @spec find([pos_integer()]) :: {pos_integer(), pos_integer()}
        def find(numbers) do
          {1, 2}
        end
      end
      """

      assert fix(code) == expected
    end
  end

  describe "leaves code unchanged (out of scope)" do
    test "single-element list type" do
      code = "@spec foo(integer()) :: [pos_integer()]"
      assert fix(code) == code
    end

    test "non-empty list type `[type, ...]`" do
      code = "@spec foo(integer()) :: [pos_integer(), ...]"
      assert fix(code) == code
    end

    test "keyword-list type" do
      code = "@spec foo(integer()) :: [ok: integer(), err: atom()]"
      assert fix(code) == code
    end

    test "literal-atom list" do
      code = "@spec foo(integer()) :: [:ok, :error]"
      assert fix(code) == code
    end

    test "tuple return type" do
      code = "@spec foo(integer()) :: {atom(), integer()}"
      assert fix(code) == code
    end

    test "simple return type" do
      code = "@spec foo(integer()) :: integer()"
      assert fix(code) == code
    end

    test "list literal in a function body" do
      code = "def foo(x), do: [x, x]"
      assert fix(code) == code
    end
  end

  describe "round-trip" do
    test "the fixed spec produces zero check issues" do
      ast = Sourceror.parse_string!(fix("@spec foo(integer()) :: [pos_integer(), pos_integer()]"))
      assert NoLiteralListTypespec.check(ast, []) == []
    end
  end
end
