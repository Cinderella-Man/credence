defmodule Credence.Pattern.NoCaseEnumAtNilCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoCaseEnumAtNil

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoCaseEnumAtNil.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags case Enum.at nil raise pattern" do
    test "basic case Enum.at nil raise identity" do
      assert flagged?("""
             def get_at(list, n) do
               case Enum.at(list, n) do
                 nil -> raise ArgumentError, "out of bounds"
                 element -> element
               end
             end
             """)
    end

    test "with custom error message" do
      assert flagged?("""
             def nth_element(list_of_lists, n) do
               Enum.map(list_of_lists, fn sublist ->
                 case Enum.at(sublist, n) do
                   nil -> raise ArgumentError, "Sublist too short"
                   element -> element
                 end
               end)
             end
             """)
    end

    test "with wildcard catch-all returning value" do
      assert flagged?("""
             def get(list, idx) do
               case Enum.at(list, idx) do
                 nil -> raise "not found"
                 v -> v
               end
             end
             """)
    end

    test "piped Enum.at" do
      assert flagged?("""
             def get(list, n) do
               case list |> Enum.at(n) do
                 nil -> raise ArgumentError, "out of bounds"
                 v -> v
               end
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag Enum.at without case nil" do
    test "plain Enum.at" do
      assert clean?("""
             def get(list, n) do
               Enum.at(list, n)
             end
             """)
    end

    test "Enum.at with default" do
      assert clean?("""
             def get(list, n) do
               Enum.at(list, n, :default)
             end
             """)
    end

    test "case Enum.at with non-nil non-identity clause" do
      assert clean?("""
             def get(list, n) do
               case Enum.at(list, n) do
                 nil -> :default
                 element -> element * 2
               end
             end
             """)
    end

    test "case Enum.at with multiple match clauses" do
      assert clean?("""
             def get(list, n) do
               case Enum.at(list, n) do
                 nil -> :missing
                 x when is_integer(x) -> x + 1
                 x -> x
               end
             end
             """)
    end

    test "case on non-Enum.at expression" do
      assert clean?("""
             def check(value) do
               case value do
                 nil -> raise "missing"
                 v -> v
               end
             end
             """)
    end

    test "wildcard catch-all returning non-identity" do
      assert clean?("""
             def get(list, idx) do
               case Enum.at(list, idx) do
                 nil -> raise "not found"
                 _ -> :ok
               end
             end
             """)
    end
  end
end
