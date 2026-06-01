defmodule Credence.Pattern.NoListDuplicateFlattenTest do
  use ExUnit.Case

  alias Credence.Pattern.NoListDuplicateFlatten

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoListDuplicateFlatten.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags List.duplicate |> List.flatten in pipe" do
    test "basic piped form" do
      assert flagged?("""
             def tile(list, n) do
               list
               |> List.duplicate(n)
               |> List.flatten()
             end
             """)
    end

    test "with variable for repetitions" do
      assert flagged?("""
             def repeat(chars, times) do
               chars
               |> List.duplicate(times)
               |> List.flatten()
             end
             """)
    end

    test "inside a pipeline with other steps" do
      assert flagged?("""
             def build(list, n) do
               list
               |> Enum.map(&to_string/1)
               |> List.duplicate(n)
               |> List.flatten()
             end
             """)
    end

    test "pipe ending with == comparison" do
      assert flagged?("""
             def repeated?(candidate, original, n) do
               candidate
               |> List.duplicate(n)
               |> List.flatten() == original
             end
             """)
    end
  end

  describe "flags List.flatten(List.duplicate(...)) nested form" do
    test "basic nested form" do
      assert flagged?("""
             def tile(list, n) do
               List.flatten(List.duplicate(list, n))
             end
             """)
    end

    test "nested with integer literal" do
      assert flagged?("""
             def triple(list) do
               List.flatten(List.duplicate(list, 3))
             end
             """)
    end
  end

  describe "flags List.duplicate |> Enum.concat in pipe" do
    test "basic piped form" do
      assert flagged?("""
             def tile(list, n) do
               list
               |> List.duplicate(n)
               |> Enum.concat()
             end
             """)
    end

    test "with variable for repetitions" do
      assert flagged?("""
             def repeat(chars, times) do
               chars
               |> List.duplicate(times)
               |> Enum.concat()
             end
             """)
    end
  end

  describe "flags Enum.concat(List.duplicate(...)) nested form" do
    test "basic nested form" do
      assert flagged?("""
             def tile(list, n) do
               Enum.concat(List.duplicate(list, n))
             end
             """)
    end

    test "nested with integer literal" do
      assert flagged?("""
             def triple(list) do
               Enum.concat(List.duplicate(list, 3))
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag List.duplicate without flatten" do
    test "standalone List.duplicate" do
      assert clean?("""
             def dup(list, n) do
               List.duplicate(list, n)
             end
             """)
    end
  end

  describe "does not flag List.flatten without List.duplicate" do
    test "standalone List.flatten" do
      assert clean?("""
             def flat(list) do
               List.flatten(list)
             end
             """)
    end

    test "flatten of other expression" do
      assert clean?("""
             def flat(lists) do
               List.flatten(Enum.map(lists, &process/1))
             end
             """)
    end
  end

  describe "does not flag Enum.concat without List.duplicate" do
    test "standalone Enum.concat" do
      assert clean?("""
             def concat(lists) do
               Enum.concat(lists)
             end
             """)
    end

    test "concat of two lists" do
      assert clean?("""
             def join(a, b) do
               Enum.concat(a, b)
             end
             """)
    end
  end

  describe "does not flag Enum.flat_map" do
    test "already idiomatic" do
      assert clean?("""
             def tile(list, n) do
               Enum.flat_map(1..n, fn _ -> list end)
             end
             """)
    end
  end

  describe "does not flag other List functions" do
    test "List.duplicate piped to something else" do
      assert clean?("""
             def dup(list, n) do
               list
               |> List.duplicate(n)
               |> List.last()
             end
             """)
    end
  end
end
