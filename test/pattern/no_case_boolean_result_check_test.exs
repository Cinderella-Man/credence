defmodule Credence.Pattern.NoCaseBooleanResultCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoCaseBooleanResult

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoCaseBooleanResult.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags case with boolean results from atom patterns" do
    test "atom patterns, true then false" do
      assert flagged?("""
             case result do
               :ok -> true
               :no -> false
             end
             """)
    end

    test "atom patterns, false then true (flipped)" do
      assert flagged?("""
             case result do
               :ok -> false
               :no -> true
             end
             """)
    end

    test "atom and wildcard, true then false" do
      assert flagged?("""
             case result do
               :ok -> true
               _ -> false
             end
             """)
    end

    test "wildcard and atom, false then true" do
      assert flagged?("""
             case result do
               :ok -> false
               _ -> true
             end
             """)
    end

    test "inline case" do
      assert flagged?(~S"case check(x) do :ok -> true; :no -> false end")
    end

    test "nested in function def" do
      assert flagged?("""
             defp is_increasing?([head | tail]) do
               case check_increasing(tail, head) do
                 :ok -> true
                 :no -> false
               end
             end
             """)
    end

    test "error/ok pair" do
      assert flagged?("""
             case File.read(path) do
               {:ok, _} -> true
               {:error, _} -> false
             end
             """)
    end

    test "flags multiple occurrences" do
      code = """
      defmodule Example do
        def foo(x) do
          case check_a(x) do
            :ok -> true
            :no -> false
          end
        end

        def bar(x) do
          case check_b(x) do
            :ok -> false
            :no -> true
          end
        end
      end
      """

      assert length(check(code)) == 2
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # PIPED CASE — expr |> case do ... end
  # ═══════════════════════════════════════════════════════════════════

  describe "flags piped case with boolean results" do
    test "simple pipe into case" do
      assert flagged?("""
             check(x)
             |> case do
               :ok -> true
               :no -> false
             end
             """)
    end

    test "pipe chain into case" do
      assert flagged?("""
             x
             |> validate()
             |> normalize()
             |> case do
               :ok -> true
               _ -> false
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag legitimate case statements" do
    test "case with boolean patterns (handled by no_case_true_false)" do
      assert clean?("""
             case x > 0 do
               true -> :positive
               false -> :negative
             end
             """)
    end

    test "case with non-boolean results" do
      assert clean?("""
             case result do
               :ok -> :success
               :error -> :failure
             end
             """)
    end

    test "case with three clauses" do
      assert clean?("""
             case result do
               :ok -> true
               :error -> false
               :timeout -> false
             end
             """)
    end

    test "case with tuple patterns and complex bodies" do
      assert clean?("""
             case File.read(path) do
               {:ok, content} -> content
               {:error, reason} -> raise reason
             end
             """)
    end

    test "case with non-boolean variable pattern" do
      assert clean?("""
             case x do
               :ok -> :proceed
               :error -> :halt
             end
             """)
    end

    test "case with single clause" do
      assert clean?("""
             case x do
               :ok -> true
             end
             """)
    end

    test "case with both same boolean result" do
      assert clean?("""
             case x do
               :ok -> true
               :no -> true
             end
             """)
    end

    test "case with non-boolean atom results" do
      assert clean?("""
             case validate(input) do
               :ok -> :proceed
               :error -> :halt
             end
             """)
    end
  end
end
