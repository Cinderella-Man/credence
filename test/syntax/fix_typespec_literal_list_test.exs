defmodule Credence.Syntax.FixTypespecLiteralListTest do
  use ExUnit.Case

  alias Credence.Syntax.FixTypespecLiteralList

  defp analyze(code) do
    FixTypespecLiteralList.analyze(code)
  end

  defp fix(code) do
    FixTypespecLiteralList.fix(code)
  end

  # ── detection ────────────────────────────────────────────────────

  describe "detection" do
    test "detects literal list in return type" do
      code = "@spec foo(integer()) :: [pos_integer(), pos_integer()]"
      assert [_issue] = analyze(code)
    end

    test "detects literal list with different types" do
      code = "@spec foo(integer()) :: [atom(), integer()]"
      assert [_issue] = analyze(code)
    end

    test "does not flag single-element list type" do
      code = "@spec foo(integer()) :: [pos_integer()]"
      assert [] = analyze(code)
    end

    test "does not flag tuple return type" do
      code = "@spec foo(integer()) :: {atom(), integer()}"
      assert [] = analyze(code)
    end

    test "does not flag simple return type" do
      code = "@spec foo(integer()) :: integer()"
      assert [] = analyze(code)
    end

    test "does not flag union return type" do
      code = "@spec foo(integer()) :: :ok | :error"
      assert [] = analyze(code)
    end

    test "does not flag non-spec lines" do
      code = "def foo(x), do: [x, x]"
      assert [] = analyze(code)
    end
  end

  # ── fix ──────────────────────────────────────────────────────────

  describe "fix" do
    test "converts literal list to tuple" do
      assert fix("@spec foo(integer()) :: [pos_integer(), pos_integer()]") ==
               "@spec foo(integer()) :: {pos_integer(), pos_integer()}"
    end

    test "converts literal list with different types" do
      assert fix("@spec foo(integer()) :: [atom(), integer()]") ==
               "@spec foo(integer()) :: {atom(), integer()}"
    end

    test "converts three-element literal list" do
      assert fix("@spec foo(integer()) :: [atom(), integer(), string()]") ==
               "@spec foo(integer()) :: {atom(), integer(), string()}"
    end

    test "preserves indentation" do
      assert fix("  @spec foo(integer()) :: [pos_integer(), pos_integer()]") ==
               "  @spec foo(integer()) :: {pos_integer(), pos_integer()}"
    end

    test "handles complex parameter types" do
      assert fix("@spec foo(list(integer())) :: [pos_integer(), pos_integer()]") ==
               "@spec foo(list(integer())) :: {pos_integer(), pos_integer()}"
    end

    test "handles bang function" do
      assert fix("@spec foo!(integer()) :: [atom(), integer()]") ==
               "@spec foo!(integer()) :: {atom(), integer()}"
    end

    test "handles question mark function" do
      assert fix("@spec foo?(integer()) :: [atom(), integer()]") ==
               "@spec foo?(integer()) :: {atom(), integer()}"
    end
  end

  # ── no-ops ───────────────────────────────────────────────────────

  describe "no-ops" do
    test "single-element list type unchanged" do
      code = "@spec foo(integer()) :: [pos_integer()]"
      assert fix(code) == code
    end

    test "tuple return type unchanged" do
      code = "@spec foo(integer()) :: {atom(), integer()}"
      assert fix(code) == code
    end

    test "simple return type unchanged" do
      code = "@spec foo(integer()) :: integer()"
      assert fix(code) == code
    end

    test "union return type unchanged" do
      code = "@spec foo(integer()) :: :ok | :error"
      assert fix(code) == code
    end

    test "list with nested tuple unchanged" do
      code = "@spec foo(integer()) :: [{atom(), integer()}]"
      assert fix(code) == code
    end

    test "no spec at all unchanged" do
      code = "def foo(x), do: x + 1"
      assert fix(code) == code
    end
  end

  # ── realistic context ────────────────────────────────────────────

  describe "realistic context" do
    test "fixes spec in module context" do
      code = """
      defmodule Solution do
        @spec find_missing([pos_integer()]) :: [pos_integer(), pos_integer()]
        def find_missing(numbers) do
          [1, 2]
        end
      end
      """

      expected = """
      defmodule Solution do
        @spec find_missing([pos_integer()]) :: {pos_integer(), pos_integer()}
        def find_missing(numbers) do
          [1, 2]
        end
      end
      """

      assert fix(code) == expected
    end

    test "preserves surrounding code" do
      code = """
      defmodule Solution do
        @moduledoc "Finds missing numbers"
        @spec find_missing_and_duplicated([pos_integer()]) :: [pos_integer(), pos_integer()]
        def find_missing_and_duplicated(numbers) do
          [1, 2]
        end
      end
      """

      expected = """
      defmodule Solution do
        @moduledoc "Finds missing numbers"
        @spec find_missing_and_duplicated([pos_integer()]) :: {pos_integer(), pos_integer()}
        def find_missing_and_duplicated(numbers) do
          [1, 2]
        end
      end
      """

      assert fix(code) == expected
    end
  end

  # ── round-trip ───────────────────────────────────────────────────

  describe "round-trip" do
    test "fixed spec produces zero analyze issues" do
      code = "@spec foo(integer()) :: [pos_integer(), pos_integer()]"
      assert analyze(fix(code)) == []
    end
  end
end
