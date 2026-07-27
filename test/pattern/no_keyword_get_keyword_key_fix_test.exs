defmodule Credence.Pattern.NoKeywordGetKeywordKeyFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoKeywordGetKeywordKey

  # ── rewrites keyword-literal keys ─────────────────────────────

  describe "rewrites keyword-literal keys" do
    test "partial: false" do
      input = "Keyword.get(opts, partial: false)"
      expected = "Keyword.get(opts, :partial, false)"
      confirm_fix(fix(NoKeywordGetKeywordKey, input), expected)
    end

    test "on_conflict: :replace" do
      input = "Keyword.get(opts, on_conflict: :replace)"
      expected = "Keyword.get(opts, :on_conflict, :replace)"
      confirm_fix(fix(NoKeywordGetKeywordKey, input), expected)
    end

    test "in assignment" do
      input = ~S'partial? = Keyword.get(opts, partial: false)'
      expected = "partial? = Keyword.get(opts, :partial, false)"
      confirm_fix(fix(NoKeywordGetKeywordKey, input), expected)
    end
  end

  # ── does not touch correct code ───────────────────────────────

  describe "does not touch correct code" do
    test "atom key with default (already correct)" do
      code = "Keyword.get(opts, :partial, false)"
      confirm_fix(fix(NoKeywordGetKeywordKey, code), code)
    end

    test "atom key without default (already correct)" do
      code = "Keyword.get(opts, :name)"
      confirm_fix(fix(NoKeywordGetKeywordKey, code), code)
    end

    test "variable key with default" do
      code = "Keyword.get(opts, key, false)"
      confirm_fix(fix(NoKeywordGetKeywordKey, code), code)
    end
  end
end
