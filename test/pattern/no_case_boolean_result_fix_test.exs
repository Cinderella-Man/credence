defmodule Credence.Pattern.NoCaseBooleanResultFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoCaseBooleanResult

  defp fix(code) do
    ast = Sourceror.parse_string!(code)
    patches = NoCaseBooleanResult.fix_patches(ast, source: code)

    case patches do
      [] -> code
      _ -> Sourceror.patch_string(code, patches)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIXABLE — wildcard + literal pattern → match?/2
  # ═══════════════════════════════════════════════════════════════════

  describe "rewrites wildcard cases to match?/2" do
    test "atom pattern -> true; _ -> false" do
      result = fix("""
      case result do
        :ok -> true
        _ -> false
      end
      """)

      assert String.contains?(result, "match?(:ok, result)")
      refute String.contains?(result, "case")
    end

    test "atom pattern -> false; _ -> true" do
      result = fix("""
      case result do
        :ok -> false
        _ -> true
      end
      """)

      assert String.contains?(result, "not match?(:ok, result)")
      refute String.contains?(result, "case")
    end

    test "_ -> false; atom pattern -> true" do
      result = fix("""
      case result do
        _ -> false
        :ok -> true
      end
      """)

      assert String.contains?(result, "match?(:ok, result)")
      refute String.contains?(result, "case")
    end

    test "_ -> true; atom pattern -> false" do
      result = fix("""
      case result do
        _ -> true
        :ok -> false
      end
      """)

      assert String.contains?(result, "not match?(:ok, result)")
      refute String.contains?(result, "case")
    end

    test "tuple pattern -> true; _ -> false" do
      result = fix("""
      case File.read(path) do
        {:ok, _} -> true
        _ -> false
      end
      """)

      assert String.contains?(result, "match?")
      assert String.contains?(result, "{:ok, _}")
      refute String.contains?(result, "case")
    end

    test "integer pattern -> true; _ -> false" do
      result = fix("""
      case status do
        0 -> true
        _ -> false
      end
      """)

      assert String.contains?(result, "match?(0, status)")
      refute String.contains?(result, "case")
    end

    test "piped case with wildcard" do
      result = fix("""
      result
      |> check()
      |> case do
        :ok -> true
        _ -> false
      end
      """)

      assert String.contains?(result, "match?")
      refute String.contains?(result, "case")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NOT FIXABLE — no patches returned
  # ═══════════════════════════════════════════════════════════════════

  describe "does not fix cases without wildcard" do
    test "two specific atom patterns" do
      code = """
      case result do
        :ok -> true
        :no -> false
      end
      """

      assert fix(code) == code
    end

    test "variable pattern (not a useful match? rewrite)" do
      code = """
      case result do
        x -> true
        _ -> false
      end
      """

      assert fix(code) == code
    end
  end
end
