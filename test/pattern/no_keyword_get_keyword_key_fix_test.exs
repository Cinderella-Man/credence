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

    test "explicit brackets around the keyword list" do
      input = "Keyword.get(opts, [partial: false])"
      expected = "Keyword.get(opts, :partial, false)"
      confirm_fix(fix(NoKeywordGetKeywordKey, input), expected)
    end

    test "quoted atom key" do
      input = ~S'Keyword.get(opts, "my-key": 1)'
      expected = ~S'Keyword.get(opts, :"my-key", 1)'
      confirm_fix(fix(NoKeywordGetKeywordKey, input), expected)
    end

    test "call expression as value" do
      input = "Keyword.get(opts, timeout: default_timeout())"
      expected = "Keyword.get(opts, :timeout, default_timeout())"
      confirm_fix(fix(NoKeywordGetKeywordKey, input), expected)
    end

    test "keyword list as value" do
      input = "Keyword.get(opts, defaults: [a: 1, b: 2])"
      expected = "Keyword.get(opts, :defaults, a: 1, b: 2)"
      confirm_fix(fix(NoKeywordGetKeywordKey, input), expected)
    end

    test "string value" do
      input = ~S'Keyword.get(opts, name: "café 🚀")'
      expected = ~S'Keyword.get(opts, :name, "café 🚀")'
      confirm_fix(fix(NoKeywordGetKeywordKey, input), expected)
    end

    test "list arg is a call" do
      input = "Keyword.get(fetch_opts(), partial: false)"
      expected = "Keyword.get(fetch_opts(), :partial, false)"
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

    test "piped Keyword.get with atom key and keyword-list default (valid /3)" do
      code = "opts |> Keyword.get(:key, partial: false)"
      confirm_fix(fix(NoKeywordGetKeywordKey, code), code)
    end

    test "3-arg Keyword.get with keyword-list default (valid /3)" do
      code = "Keyword.get(opts, :key, partial: false)"
      confirm_fix(fix(NoKeywordGetKeywordKey, code), code)
    end

    test "multi-element keyword list (intended key ambiguous — deliberately skipped)" do
      code = "Keyword.get(opts, a: 1, b: 2)"
      confirm_fix(fix(NoKeywordGetKeywordKey, code), code)
    end

    test "explicit tuple syntax (deliberately skipped — no keyword shorthand)" do
      code = "Keyword.get(opts, [{:partial, false}])"
      confirm_fix(fix(NoKeywordGetKeywordKey, code), code)
    end

    test "piped keyword-list-only call (crashes too, but deliberately skipped)" do
      code = "opts |> Keyword.get(partial: false)"
      confirm_fix(fix(NoKeywordGetKeywordKey, code), code)
    end
  end
end
