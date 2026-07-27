defmodule Credence.Pattern.NoKeywordGetKeywordKeyCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoKeywordGetKeywordKey

  # ── flags keyword-literal keys ────────────────────────────────

  describe "flags keyword-literal keys" do
    test "partial: false" do
      assert [%Issue{rule: :no_keyword_get_keyword_key}] =
               check(NoKeywordGetKeywordKey, "Keyword.get(opts, partial: false)")
    end

    test "on_conflict: :replace" do
      assert [%Issue{}] =
               check(NoKeywordGetKeywordKey, "Keyword.get(opts, on_conflict: :replace)")
    end

    test "verbose: true" do
      assert [%Issue{}] =
               check(NoKeywordGetKeywordKey, "Keyword.get(opts, verbose: true)")
    end
  end

  # ── flags in various contexts ─────────────────────────────────

  describe "flags in various contexts" do
    test "in assignment" do
      assert [%Issue{}] =
               check(NoKeywordGetKeywordKey, ~s'partial? = Keyword.get(opts, partial: false)')
    end

    test "as function argument" do
      assert [%Issue{}] =
               check(NoKeywordGetKeywordKey, "do_something(Keyword.get(opts, partial: false))")
    end

    test "multiple in one module" do
      code = """
      defmodule E do
        def read(opts) do
          partial? = Keyword.get(opts, partial: false)
          on_conflict = Keyword.get(opts, on_conflict: :replace)
          {partial?, on_conflict}
        end
      end
      """

      assert length(check(NoKeywordGetKeywordKey, code)) == 2
    end
  end

  # ── does NOT flag ─────────────────────────────────────────────

  describe "does NOT flag" do
    test "atom key with default (correct 3-arg form)" do
      assert check(NoKeywordGetKeywordKey, "Keyword.get(opts, :partial, false)") == []
    end

    test "atom key without default (correct 2-arg form)" do
      assert check(NoKeywordGetKeywordKey, "Keyword.get(opts, :name)") == []
    end

    test "variable key" do
      assert check(NoKeywordGetKeywordKey, "Keyword.get(opts, key)") == []
    end

    test "variable key with default" do
      assert check(NoKeywordGetKeywordKey, "Keyword.get(opts, key, false)") == []
    end

    test "piped Keyword.get with atom key" do
      assert check(NoKeywordGetKeywordKey, "opts |> Keyword.get(:partial, false)") == []
    end

    test "Map.get with keyword list (different module)" do
      assert check(NoKeywordGetKeywordKey, "Map.get(m, partial: false)") == []
    end

    test "Keyword.fetch with keyword list (different function)" do
      assert check(NoKeywordGetKeywordKey, "Keyword.fetch(opts, partial: false)") == []
    end

    test "no Keyword.get at all" do
      assert check(NoKeywordGetKeywordKey, "Enum.map(list, & &1)") == []
    end
  end

  # ── metadata ──────────────────────────────────────────────────

  describe "metadata" do
    test "meta.line is set" do
      [issue] = check(NoKeywordGetKeywordKey, "Keyword.get(opts, partial: false)")
      assert issue.meta.line != nil
    end
  end
end
