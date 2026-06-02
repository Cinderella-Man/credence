defmodule Credence.Pattern.NoListDuplicateJoinTest do
  use ExUnit.Case

  alias Credence.Pattern.NoListDuplicateJoin

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoListDuplicateJoin.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags List.duplicate |> Enum.join in pipe" do
    test "basic piped form" do
      assert flagged?("""
             def repeat(str, n) do
               str
               |> List.duplicate(n)
               |> Enum.join()
             end
             """)
    end

    test "with variable for repetitions" do
      assert flagged?("""
             def build(pattern, times) do
               pattern
               |> List.duplicate(times)
               |> Enum.join()
             end
             """)
    end

    test "inside a pipeline with other steps" do
      assert flagged?("""
             def make(str, n) do
               str
               |> String.trim()
               |> List.duplicate(n)
               |> Enum.join()
             end
             """)
    end
  end

  describe "flags Enum.join(List.duplicate(...)) nested form" do
    test "basic nested form" do
      assert flagged?("""
             def repeat(str, n) do
               Enum.join(List.duplicate(str, n))
             end
             """)
    end

    test "nested with integer literal" do
      assert flagged?("""
             def triple(str) do
               Enum.join(List.duplicate(str, 3))
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag List.duplicate without Enum.join" do
    test "standalone List.duplicate" do
      assert clean?("""
             def dup(str, n) do
               List.duplicate(str, n)
             end
             """)
    end
  end

  describe "does not flag Enum.join without List.duplicate" do
    test "standalone Enum.join" do
      assert clean?("""
             def join(list) do
               Enum.join(list)
             end
             """)
    end

    test "Enum.join of a map operation" do
      assert clean?("""
             def join(list) do
               Enum.join(Enum.map(list, &to_string/1))
             end
             """)
    end
  end

  describe "does not flag Enum.join with separator" do
    test "Enum.join with separator arg" do
      assert clean?("""
             def repeat(str, n) do
               str
               |> List.duplicate(n)
               |> Enum.join(", ")
             end
             """)
    end
  end

  describe "does not flag String.duplicate" do
    test "already idiomatic" do
      assert clean?("""
             def repeat(str, n) do
               String.duplicate(str, n)
             end
             """)
    end
  end

  describe "does not flag other List functions" do
    test "List.duplicate piped to something else" do
      assert clean?("""
             def dup(str, n) do
               str
               |> List.duplicate(n)
               |> List.last()
             end
             """)
    end
  end
end
