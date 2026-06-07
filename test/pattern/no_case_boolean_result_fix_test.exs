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

      expected = """
      match?(:ok, result)
      """

      assert fix(NoCaseBooleanResult, code) == expected
    end

    test "atom pattern -> false; _ -> true" do
      code = """
      case result do
        :ok -> false
        _ -> true
      end
      """

      expected = """
      not match?(:ok, result)
      """

      assert fix(NoCaseBooleanResult, code) == expected
    end

    test "tuple pattern -> true; _ -> false" do
      code = """
      case File.read(path) do
        {:ok, _} -> true
        _ -> false
      end
      """

      expected = """
      match?({:ok, _}, File.read(path))
      """

      assert fix(NoCaseBooleanResult, code) == expected
    end

    test "integer pattern -> true; _ -> false" do
      code = """
      case status do
        0 -> true
        _ -> false
      end
      """

      expected = """
      match?(0, status)
      """

      assert fix(NoCaseBooleanResult, code) == expected
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

      assert fix(NoCaseBooleanResult, code) == expected
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

      assert fix(NoCaseBooleanResult, code) == code
    end

    test "variable pattern, then wildcard (case is constant)" do
      code = """
      case result do
        x -> true
        _ -> false
      end
      """

      assert fix(NoCaseBooleanResult, code) == code
    end

    test "wildcard FIRST, false then true (second clause is dead)" do
      code = """
      case result do
        _ -> false
        :ok -> true
      end
      """

      assert fix(NoCaseBooleanResult, code) == code
    end

    test "wildcard FIRST, true then false (second clause is dead)" do
      code = """
      case result do
        _ -> true
        :ok -> false
      end
      """

      assert fix(NoCaseBooleanResult, code) == code
    end
  end
end
