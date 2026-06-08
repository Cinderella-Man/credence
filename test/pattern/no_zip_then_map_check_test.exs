defmodule Credence.Pattern.NoZipThenMapCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoZipThenMap

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags Enum.zip |> Enum.map with tuple destructuring" do
    test "pipe form: zip piped to map" do
      assert flagged?(NoZipThenMap, """
             Enum.zip(names, scores)
             |> Enum.map(fn {name, score} -> {name, score * 2} end)
             """)
    end

    test "pipe form with multiline fn" do
      assert flagged?(NoZipThenMap, """
             Enum.zip(keys, values)
             |> Enum.map(fn {k, v} ->
               {k, v + 1}
             end)
             """)
    end

    test "nested form: map wrapping zip" do
      assert flagged?(NoZipThenMap, """
             Enum.map(Enum.zip(names, scores), fn {name, score} ->
               {name, score * 2}
             end)
             """)
    end

    test "nested form single line" do
      assert flagged?(NoZipThenMap, """
             Enum.map(Enum.zip(a, b), fn {x, y} -> x + y end)
             """)
    end

    test "zip in longer pipeline" do
      assert flagged?(NoZipThenMap, """
             list
             |> Enum.filter(&positive?/1)
             |> Enum.zip(other)
             |> Enum.map(fn {a, b} -> a + b end)
             """)
    end

    test "pipe with different variable names" do
      assert flagged?(NoZipThenMap, """
             Enum.zip(xs, ys)
             |> Enum.map(fn {left, right} -> left * right end)
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag guarded fns (out of fixable scope)" do
    # The fix can't drop/rebuild the guard, so check must not flag it either.
    test "pipe form with guard" do
      assert clean?(NoZipThenMap, """
             Enum.zip(names, ages)
             |> Enum.map(fn {name, age} when is_binary(name) -> {name, age} end)
             """)
    end
  end

  describe "does not flag Enum.zip/1 over a list at pipe head" do
    # `Enum.zip([names, scores])` is the real zip/1, not a pipe-elided zip/2.
    test "list-arg zip at pipe head" do
      assert clean?(NoZipThenMap, """
             Enum.zip([names, scores])
             |> Enum.map(fn {a, b} -> a + b end)
             """)
    end
  end

  describe "does not flag Enum.zip alone" do
    test "zip without map" do
      assert clean?(NoZipThenMap, """
             Enum.zip(names, scores)
             """)
    end

    test "zip piped to something other than map" do
      assert clean?(NoZipThenMap, """
             Enum.zip(names, scores)
             |> Enum.filter(fn {n, _s} -> n != "" end)
             """)
    end
  end

  describe "does not flag map without tuple destructuring" do
    test "map with single-arg fn (not destructuring)" do
      assert clean?(NoZipThenMap, """
             [1, 2, 3]
             |> Enum.zip([4, 5, 6])
             |> Enum.map(fn pair -> elem(pair, 0) end)
             """)
    end

    test "map with identity fn" do
      assert clean?(NoZipThenMap, """
             Enum.zip(a, b) |> Enum.map(&Function.identity/1)
             """)
    end
  end

  describe "does not flag Enum.zip_with (already idiomatic)" do
    test "zip_with usage" do
      assert clean?(NoZipThenMap, """
             Enum.zip_with(names, scores, fn name, score ->
               {name, score * 2}
             end)
             """)
    end
  end

  describe "does not flag Enum.zip/1" do
    test "single-argument zip" do
      assert clean?(NoZipThenMap, """
             Enum.zip([names, scores])
             """)
    end
  end

  describe "does not flag non-Enum modules" do
    test "Stream.zip |> Stream.map" do
      assert clean?(NoZipThenMap, """
             Stream.zip(names, scores)
             |> Stream.map(fn {n, s} -> {n, s} end)
             """)
    end
  end

  describe "does not flag tuple pattern with literals" do
    test "pattern matching on literal values" do
      assert clean?(NoZipThenMap, """
             Enum.map(some_list, fn {1, 2} -> :match end)
             """)
    end
  end

  describe "does not flag 3+ element tuple destructuring" do
    test "three-element tuple from Enum.zip/1" do
      assert clean?(NoZipThenMap, """
             Enum.map(some_list, fn {a, b, c} -> a + b + c end)
             """)
    end
  end
end
