defmodule Credence.Pattern.NoIsNilGuardCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoIsNilGuard

  # ── flags sole is_nil guard ────────────────────────────────────

  describe "flags sole is_nil guard" do
    test "def one-liner, param unused" do
      assert [%Issue{rule: :no_is_nil_guard}] =
               check(NoIsNilGuard, "def foo(x) when is_nil(x), do: :bar")
    end

    test "defp one-liner" do
      assert [%Issue{}] =
               check(NoIsNilGuard, "defp foo(x) when is_nil(x), do: :bar")
    end

    test "multi-param, is_nil on first" do
      assert [%Issue{}] =
               check(NoIsNilGuard, "def foo(x, y) when is_nil(x), do: y")
    end

    test "multi-param, is_nil on second" do
      assert [%Issue{}] =
               check(NoIsNilGuard, "def foo(x, y) when is_nil(y), do: x")
    end

    test "block form" do
      code = """
      def foo(x) when is_nil(x) do
        :bar
      end
      """

      assert [%Issue{}] = check(NoIsNilGuard, code)
    end

    test "param used in body" do
      assert [%Issue{}] =
               check(NoIsNilGuard, "def foo(x) when is_nil(x), do: inspect(x)")
    end
  end

  # ── flags is_nil combined with and ─────────────────────────────

  describe "flags is_nil combined with and" do
    test "is_nil first" do
      assert [%Issue{}] =
               check(NoIsNilGuard, "def foo(x, y) when is_nil(x) and is_binary(y), do: :ok")
    end

    test "is_nil second" do
      assert [%Issue{}] =
               check(NoIsNilGuard, "def foo(x, y) when is_binary(y) and is_nil(x), do: :ok")
    end

    test "both params nil" do
      assert [%Issue{}] =
               check(NoIsNilGuard, "def foo(x, y) when is_nil(x) and is_nil(y), do: :ok")
    end
  end

  # ── flags multiple violations ──────────────────────────────────

  describe "flags multiple violations" do
    test "two clauses in one module" do
      code = """
      defmodule E do
        def foo(x) when is_nil(x), do: :bar
        def bar(y) when is_nil(y), do: :baz
      end
      """

      assert length(check(NoIsNilGuard, code)) == 2
    end
  end

  # ── does NOT flag ──────────────────────────────────────────────

  describe "does NOT flag" do
    test "already pattern matched nil" do
      assert check(NoIsNilGuard, "def foo(nil), do: :bar") == []
    end

    test "negated with not" do
      assert check(NoIsNilGuard, "def foo(x) when not is_nil(x), do: :ok") == []
    end

    test "negated with !" do
      assert check(NoIsNilGuard, "def foo(x) when !is_nil(x), do: :ok") == []
    end

    test "or condition" do
      assert check(NoIsNilGuard, "def foo(x) when is_nil(x) or is_atom(x), do: :ok") == []
    end

    test "non-variable argument" do
      assert check(NoIsNilGuard, "def foo(x) when is_nil(hd(x)), do: :ok") == []
    end

    test "no is_nil in guard" do
      assert check(NoIsNilGuard, "def foo(x) when is_binary(x), do: :ok") == []
    end

    test "no guard at all" do
      assert check(NoIsNilGuard, "def foo(x), do: x") == []
    end

    test "is_nil outside of function guard" do
      code = """
      defmodule E do
        def foo(x) do
          if is_nil(x), do: :bar, else: x
        end
      end
      """

      assert check(NoIsNilGuard, code) == []
    end

    test "destructured binding (not a top-level param)" do
      assert check(NoIsNilGuard, "def foo(%{key: val}) when is_nil(val), do: :default") == []
    end
  end

  # ── metadata ───────────────────────────────────────────────────

  describe "metadata" do
    test "meta.line is set" do
      [issue] =
        check(NoIsNilGuard, "def foo(x) when is_nil(x), do: :bar")

      assert issue.meta.line != nil
    end
  end
end
