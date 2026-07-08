defmodule Credence.Pattern.NoKeywordGetWithAtomFirstArgCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoKeywordGetWithAtomFirstArg

  # ── flags atom first argument ──────────────────────────────────

  describe "flags atom first argument" do
    test "2-arg with fn default" do
      assert [%Issue{rule: :no_keyword_get_with_atom_first_arg}] =
               check(NoKeywordGetWithAtomFirstArg, "Keyword.get(:clock, fn -> :default end)")
    end

    test "2-arg with integer default" do
      assert [%Issue{}] =
               check(NoKeywordGetWithAtomFirstArg, "Keyword.get(:timeout, 5000)")
    end

    test "2-arg with atom default" do
      assert [%Issue{}] =
               check(NoKeywordGetWithAtomFirstArg, "Keyword.get(:key, :fallback)")
    end

    test "3-arg with atom first" do
      assert [%Issue{}] =
               check(NoKeywordGetWithAtomFirstArg, "Keyword.get(:key, :lookup, :fallback)")
    end

    test "nil as first arg" do
      assert [%Issue{}] =
               check(NoKeywordGetWithAtomFirstArg, "Keyword.get(nil, :default)")
    end

    test "true as first arg" do
      assert [%Issue{}] =
               check(NoKeywordGetWithAtomFirstArg, "Keyword.get(true, :default)")
    end
  end

  # ── flags in various contexts ──────────────────────────────────

  describe "flags in various contexts" do
    test "in assignment" do
      assert [%Issue{}] =
               check(NoKeywordGetWithAtomFirstArg, "clock = Keyword.get(:clock, fn -> :default end)")
    end

    test "as function argument" do
      assert [%Issue{}] =
               check(NoKeywordGetWithAtomFirstArg, "do_something(Keyword.get(:key, :val))")
    end

    test "in module body" do
      code = """
      defmodule Example do
        def init(:ok) do
          clock = Keyword.get(:clock, fn -> :default end)
          %{clock: clock}
        end
      end
      """

      assert [%Issue{}] = check(NoKeywordGetWithAtomFirstArg, code)
    end
  end

  # ── flags piped calls ─────────────────────────────────────────

  describe "flags piped calls" do
    test "piped atom with 1-arg call" do
      assert [%Issue{}] =
               check(NoKeywordGetWithAtomFirstArg, ":clock |> Keyword.get(:key)")
    end

    test "piped atom with 2-arg call" do
      assert [%Issue{}] =
               check(NoKeywordGetWithAtomFirstArg, ":atom |> Keyword.get(:key, :default)")
    end
  end

  # ── flags multiple violations ──────────────────────────────────

  describe "flags multiple violations" do
    test "two in one module" do
      code = """
      defmodule E do
        def a, do: Keyword.get(:key1, :val1)
        def b, do: Keyword.get(:key2, :val2)
      end
      """

      assert length(check(NoKeywordGetWithAtomFirstArg, code)) == 2
    end
  end

  # ── does NOT flag ──────────────────────────────────────────────

  describe "does NOT flag" do
    test "variable first arg" do
      assert check(NoKeywordGetWithAtomFirstArg, "Keyword.get(opts, :name)") == []
    end

    test "variable first arg with default" do
      assert check(NoKeywordGetWithAtomFirstArg, ~S'Keyword.get(opts, :name, "default")') == []
    end

    test "piped variable with atom key" do
      assert check(NoKeywordGetWithAtomFirstArg, "opts |> Keyword.get(:name)") == []
    end

    test "piped variable with atom key and default" do
      assert check(NoKeywordGetWithAtomFirstArg, "opts |> Keyword.get(:name, :default)") == []
    end

    test "Map.get with atom first arg (different module)" do
      assert check(NoKeywordGetWithAtomFirstArg, "Map.get(:atom, :key)") == []
    end

    test "no Keyword.get at all" do
      assert check(NoKeywordGetWithAtomFirstArg, "List.last(acc)") == []
    end

    test "Keyword.keys with atom arg (different function)" do
      assert check(NoKeywordGetWithAtomFirstArg, "Keyword.keys(:atom)") == []
    end

    test "single-arg Keyword.get (out of scope — /1 doesn't exist)" do
      assert check(NoKeywordGetWithAtomFirstArg, "Keyword.get(:atom)") == []
    end
  end

  # ── metadata ───────────────────────────────────────────────────

  describe "metadata" do
    test "meta.line is set" do
      [issue] = check(NoKeywordGetWithAtomFirstArg, "Keyword.get(:clock, :default)")
      assert issue.meta.line != nil
    end
  end
end
