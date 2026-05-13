defmodule Credence.Pattern.NoKeywordGetIntegerKeyCheckTest do
  use ExUnit.Case

  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoKeywordGetIntegerKey.check(ast, [])
  end

  describe "fixable?/0" do
    test "reports as fixable" do
      assert Credence.Pattern.NoKeywordGetIntegerKey.fixable?() == true
    end
  end

  # ── flags integer keys ─────────────────────────────────────────

  describe "flags integer keys" do
    test "negative index -1" do
      assert [%Issue{rule: :no_keyword_get_integer_key}] = check("Keyword.get(acc, -1)")
    end

    test "zero index" do
      assert [%Issue{}] = check("Keyword.get(list, 0)")
    end

    test "positive index" do
      assert [%Issue{}] = check("Keyword.get(items, 3)")
    end

    test "other negative index" do
      assert [%Issue{}] = check("Keyword.get(items, -2)")
    end
  end

  # ── flags in various contexts ──────────────────────────────────

  describe "flags in various contexts" do
    test "in assignment" do
      assert [%Issue{}] = check("prev = Keyword.get(acc, -1)")
    end

    test "in pipe" do
      assert [%Issue{}] = check("acc |> Keyword.get(-1)")
    end

    test "as function argument" do
      assert [%Issue{}] = check("do_something(Keyword.get(list, -1))")
    end
  end

  # ── flags multiple violations ──────────────────────────────────

  describe "flags multiple violations" do
    test "two in one module" do
      code = """
      defmodule E do
        def first(l), do: Keyword.get(l, 0)
        def last(l), do: Keyword.get(l, -1)
      end
      """

      assert length(check(code)) == 2
    end
  end

  # ── does NOT flag ──────────────────────────────────────────────

  describe "does NOT flag" do
    test "atom key" do
      assert check("Keyword.get(opts, :name)") == []
    end

    test "atom key with default" do
      assert check("Keyword.get(opts, :name, \"default\")") == []
    end

    test "variable key" do
      assert check("Keyword.get(opts, key)") == []
    end

    test "Map.get with integer key (maps allow integer keys)" do
      assert check("Map.get(map, -1)") == []
    end

    test "Keyword.fetch with integer key (different function)" do
      assert check("Keyword.fetch(opts, -1)") == []
    end

    test "no Keyword.get at all" do
      assert check("List.last(acc)") == []
    end
  end

  # ── metadata ───────────────────────────────────────────────────

  describe "metadata" do
    test "meta.line is set" do
      [issue] = check("Keyword.get(acc, -1)")
      assert issue.meta.line != nil
    end
  end
end
