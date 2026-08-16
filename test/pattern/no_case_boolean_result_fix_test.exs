defmodule Credence.Pattern.NoCaseBooleanResultFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoCaseBooleanResult

  # ═══════════════════════════════════════════════════════════════════
  # FIXABLE — specific pattern, then trailing wildcard → match?/2
  # ═══════════════════════════════════════════════════════════════════

  describe "rewrites wildcard-last cases to match?/2" do
    test "atom pattern -> true; _ -> false" do
      code = """
      case result do
        :ok -> true
        _ -> false
      end
      """

      expected = "match?(:ok, result)"

      confirm_fix(fix(NoCaseBooleanResult, code), expected)
    end

    test "atom pattern -> false; _ -> true" do
      code = """
      case result do
        :ok -> false
        _ -> true
      end
      """

      expected = "not match?(:ok, result)"

      confirm_fix(fix(NoCaseBooleanResult, code), expected)
    end

    test "tuple pattern -> true; _ -> false" do
      code = """
      case File.read(path) do
        {:ok, _} -> true
        _ -> false
      end
      """

      expected = "match?({:ok, _}, File.read(path))"

      confirm_fix(fix(NoCaseBooleanResult, code), expected)
    end

    test "integer pattern -> true; _ -> false" do
      code = """
      case status do
        0 -> true
        _ -> false
      end
      """

      expected = "match?(0, status)"

      confirm_fix(fix(NoCaseBooleanResult, code), expected)
    end

    test "piped case with trailing wildcard" do
      code = """
      result
      |> check()
      |> case do
        :ok -> true
        _ -> false
      end
      """

      expected = """
      match?(
        :ok,
        result
        |> check()
      )
      """

      confirm_fix(fix(NoCaseBooleanResult, code), expected)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NOT FIXABLE — left exactly as-is (different answer if rewritten)
  # ═══════════════════════════════════════════════════════════════════

  describe "leaves unsafe shapes untouched" do
    test "two specific atom patterns (no wildcard)" do
      code = """
      case result do
        :ok -> true
        :no -> false
      end
      """

      confirm_fix(fix(NoCaseBooleanResult, code), code)
    end

    test "variable pattern, then wildcard (case is constant)" do
      code = """
      case result do
        x -> true
        _ -> false
      end
      """

      confirm_fix(fix(NoCaseBooleanResult, code), code)
    end

    test "wildcard FIRST, false then true (second clause is dead)" do
      code = """
      case result do
        _ -> false
        :ok -> true
      end
      """

      confirm_fix(fix(NoCaseBooleanResult, code), code)
    end

    test "wildcard FIRST, true then false (second clause is dead)" do
      code = """
      case result do
        _ -> true
        :ok -> false
      end
      """

      confirm_fix(fix(NoCaseBooleanResult, code), code)
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
      case a do
        {:f, _} -> false
        _ -> true
      end
      """

      expected = "not match?({:f, _}, a)"

      confirm_fix(fix(Credence.Pattern.NoCaseBooleanResult, input), expected)
    end
  end
end
