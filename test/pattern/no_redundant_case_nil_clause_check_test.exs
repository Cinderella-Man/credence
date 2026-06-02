defmodule Credence.Pattern.NoRedundantCaseNilClauseCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoRedundantCaseNilClause

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoRedundantCaseNilClause.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags redundant nil clause" do
    test "nil clause with identical wildcard body" do
      assert flagged?("""
             case Map.get(map, key) do
               nil ->
                 default_action()

               prev when prev >= left ->
                 use_value(prev)

               _prev ->
                 default_action()
             end
             """)
    end

    test "single-line bodies" do
      assert flagged?(~S"""
             case x do
               nil -> 0
               n when n > 0 -> n
               _ -> 0
             end
             """)
    end

    test "multi-line identical bodies" do
      assert flagged?("""
             case Map.get(m, k) do
               nil ->
                 a = compute_default()
                 {a, acc}

               val when val >= threshold ->
                 a = transform(val)
                 {a, Map.put(acc, k, val)}

               _val ->
                 a = compute_default()
                 {a, acc}
             end
             """)
    end

    test "piped case" do
      assert flagged?("""
             map
             |> Map.get(key)
             |> case do
               nil -> :not_found
               v when v > 0 -> {:ok, v}
               _v -> :not_found
             end
             """)
    end

    test "nested in function" do
      assert flagged?("""
             defp process(char, positions, idx) do
               case Map.get(positions, char) do
                 nil ->
                   idx + 1

                 prev when prev >= idx ->
                   prev

                 _prev ->
                   idx + 1
               end
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag legitimate case statements" do
    test "nil and wildcard with different bodies" do
      assert clean?("""
             case Map.get(map, key) do
               nil -> :not_found
               val when val > 0 -> {:ok, val}
               _ -> :other
             end
             """)
    end

    test "no guard on middle clause" do
      assert clean?("""
             case x do
               nil -> :a
               :special -> :b
               _ -> :a
             end
             """)
    end

    test "only two clauses" do
      assert clean?("""
             case x do
               nil -> :nothing
               val -> {:ok, val}
             end
             """)
    end

    test "four clauses" do
      assert clean?("""
             case x do
               nil -> :a
               :one -> :b
               :two -> :c
               _ -> :a
             end
             """)
    end

    test "nil is not first clause" do
      assert clean?("""
             case x do
               val when val > 0 -> :positive
               nil -> :zero
               _ -> :other
             end
             """)
    end

    test "wildcard is not last clause" do
      assert clean?("""
             case x do
               nil -> :a
               _ -> :a
               val when val > 0 -> :b
             end
             """)
    end

    test "guard clause uses different variable" do
      assert clean?("""
             case Map.get(m, k) do
               nil -> :default
               x when x > 0 -> :positive
               y -> :default
             end
             """)
    end

    test "no nil clause" do
      assert clean?("""
             case x do
               :a -> 1
               n when n > 0 -> n
               _ -> 1
             end
             """)
    end

    test "pattern match instead of wildcard" do
      assert clean?("""
             case x do
               nil -> :a
               n when n > 0 -> :b
               {:error, _} -> :a
             end
             """)
    end
  end
end
