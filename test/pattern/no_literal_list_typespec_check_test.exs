defmodule Credence.Pattern.NoLiteralListTypespecCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoLiteralListTypespec
  alias Credence.Issue

  describe "detects" do
    test "two-element type-call list return type" do
      issues =
        check(NoLiteralListTypespec, "@spec foo(integer()) :: [pos_integer(), pos_integer()]")

      assert [%Issue{rule: :no_literal_list_typespec}] = issues
    end

    test "three-element type-call list" do
      assert [%Issue{}] =
               check(
                 NoLiteralListTypespec,
                 "@spec foo(integer()) :: [atom(), integer(), string()]"
               )
    end

    test "different element types" do
      assert [%Issue{}] =
               check(NoLiteralListTypespec, "@spec foo(integer()) :: [atom(), integer()]")
    end

    test "bang function name" do
      assert [%Issue{}] =
               check(NoLiteralListTypespec, "@spec foo!(integer()) :: [atom(), integer()]")
    end

    test "question-mark function name" do
      assert [%Issue{}] =
               check(NoLiteralListTypespec, "@spec foo?(integer()) :: [atom(), integer()]")
    end

    test "remote type elements" do
      assert [%Issue{}] =
               check(NoLiteralListTypespec, "@spec foo(integer()) :: [String.t(), atom()]")
    end

    test "inside a module, only the return type" do
      code = """
      defmodule Solution do
        @spec find([pos_integer()]) :: [pos_integer(), pos_integer()]
        def find(n), do: {1, 2}
      end
      """

      assert [%Issue{rule: :no_literal_list_typespec}] = check(NoLiteralListTypespec, code)
    end

    test "reports the spec's line number" do
      code = "defmodule M do\n  @spec foo() :: [atom(), integer()]\n  def foo, do: {1, 2}\nend\n"
      assert [%Issue{meta: %{line: 2}}] = check(NoLiteralListTypespec, code)
    end
  end

  describe "does not flag (deliberately out of scope)" do
    test "single-element list type (valid: list of type)" do
      assert check(NoLiteralListTypespec, "@spec foo(integer()) :: [pos_integer()]") == []
    end

    test "non-empty list type `[type, ...]` (valid)" do
      assert check(NoLiteralListTypespec, "@spec foo(integer()) :: [pos_integer(), ...]") == []
    end

    test "keyword-list type (valid)" do
      assert check(NoLiteralListTypespec, "@spec foo(integer()) :: [ok: integer(), err: atom()]") ==
               []
    end

    test "literal-atom list (ambiguous: likely a `:ok | :error` union)" do
      assert check(NoLiteralListTypespec, "@spec foo(integer()) :: [:ok, :error]") == []
    end

    test "tuple return type" do
      assert check(NoLiteralListTypespec, "@spec foo(integer()) :: {atom(), integer()}") == []
    end

    test "simple return type" do
      assert check(NoLiteralListTypespec, "@spec foo(integer()) :: integer()") == []
    end

    test "union return type" do
      assert check(NoLiteralListTypespec, "@spec foo(integer()) :: :ok | :error") == []
    end

    test "list literal in a function body, not a spec" do
      assert check(NoLiteralListTypespec, "def foo(x), do: [x, x]") == []
    end
  end
end
