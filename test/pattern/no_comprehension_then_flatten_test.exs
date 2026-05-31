defmodule Credence.Pattern.NoComprehensionThenFlattenTest do
  use ExUnit.Case

  alias Credence.Pattern.NoComprehensionThenFlatten

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoComprehensionThenFlatten.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags for comprehension piped to List.flatten" do
    test "basic piped form" do
      assert flagged?("""
             def pairs(list) do
               for x <- list do
                 [x, x + 1]
               end
               |> List.flatten()
             end
             """)
    end

    test "with filter and if/else body" do
      assert flagged?("""
             def divisors(n) do
               for d <- 1..n, rem(n, d) == 0 do
                 if d == div(n, d), do: d, else: [d, div(n, d)]
               end
               |> List.flatten()
             end
             """)
    end

    test "single-line piped form" do
      assert flagged?("""
             def flat(list), do: for(x <- list, do: [x, x]) |> List.flatten()
             """)
    end
  end

  describe "flags List.flatten wrapping a for comprehension" do
    test "basic nested form" do
      assert flagged?("""
             def pairs(list) do
               List.flatten(for x <- list, do: [x, x + 1])
             end
             """)
    end

    test "multiline nested form" do
      assert flagged?("""
             def expand(list) do
               List.flatten(
                 for x <- list do
                   [x, x * 2]
                 end
               )
             end
             """)
    end
  end

  describe "flags for comprehension assigned to variable then piped to List.flatten" do
    test "variable bound to for then piped" do
      assert flagged?("""
             def flat(list) do
               rows = for x <- list, do: [x, x + 1]
               rows |> List.flatten()
             end
             """)
    end

    test "variable bound to nested for then piped with more operations" do
      assert flagged?("""
             def decode(text, rows) do
               matrix =
                 for row <- 0..(rows - 1) do
                   for col <- 0..5, do: String.at(text, col * rows + row)
                 end

               matrix |> List.flatten() |> Enum.join()
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag for with :reduce" do
    test "comprehension with reduce option" do
      assert clean?("""
             def sum_even(list) do
               for x <- list, rem(x, 2) == 0, reduce: 0 do
                 acc -> acc + x
               end
               |> List.flatten()
             end
             """)
    end
  end

  describe "does not flag for with :into" do
    test "comprehension with into option" do
      assert clean?("""
             def to_map(list) do
               for x <- list, into: %{} do
                 {x, x * 2}
               end
               |> List.flatten()
             end
             """)
    end
  end

  describe "does not flag variable-bound for with :reduce piped to List.flatten" do
    test "reduce comprehension bound then piped" do
      assert clean?("""
             def sum_even(list) do
               result = for x <- list, rem(x, 2) == 0, reduce: 0 do
                 acc -> acc + x
               end
               result |> List.flatten()
             end
             """)
    end
  end

  describe "does not flag variable-bound for when not piped to List.flatten" do
    test "variable used with other operations" do
      assert clean?("""
             def go(list) do
               rows = for x <- list, do: [x, x + 1]
               Enum.map(rows, &Enum.sum/1)
             end
             """)
    end
  end

  describe "does not flag List.flatten without for" do
    test "standalone List.flatten" do
      assert clean?("""
             def flat(list) do
               List.flatten(list)
             end
             """)
    end

    test "List.flatten of Enum.map" do
      assert clean?("""
             def flat(list) do
               List.flatten(Enum.map(list, &process/1))
             end
             """)
    end
  end

  describe "does not flag for without List.flatten" do
    test "standalone for comprehension" do
      assert clean?("""
             def double(list) do
               for x <- list, do: x * 2
             end
             """)
    end

    test "for piped to other function" do
      assert clean?("""
             def count(list) do
               for x <- list, do: x * 2
               |> Enum.count()
             end
             """)
    end
  end

  describe "does not flag List.flatten inside for body" do
    test "flatten used within comprehension body" do
      assert clean?("""
             def process(list) do
               for x <- list do
                 List.flatten([x, [x + 1]])
               end
             end
             """)
    end
  end
end
