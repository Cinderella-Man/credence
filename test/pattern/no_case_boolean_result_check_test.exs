defmodule Credence.Pattern.NoCaseBooleanResultCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoCaseBooleanResult

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — specific pattern, then trailing wildcard, opposite booleans
  # ═══════════════════════════════════════════════════════════════════

  describe "flags wildcard-last boolean cases" do
    test "atom pattern, true then false" do
      assert flagged?(NoCaseBooleanResult, """
             case result do
               :ok -> true
               _ -> false
             end
             """)
    end

    test "atom pattern, false then true" do
      assert flagged?(NoCaseBooleanResult, """
             case result do
               :ok -> false
               _ -> true
             end
             """)
    end

    test "tuple pattern, true then false" do
      assert flagged?(NoCaseBooleanResult, """
             case File.read(path) do
               {:ok, _} -> true
               _ -> false
             end
             """)
    end

    test "inline case" do
      assert flagged?(NoCaseBooleanResult, ~S"case check(x) do :ok -> true; _ -> false end")
    end

    test "nested in function def" do
      assert flagged?(NoCaseBooleanResult, """
             defp is_increasing?([head | tail]) do
               case check_increasing(tail, head) do
                 :ok -> true
                 _ -> false
               end
             end
             """)
    end

    test "flags multiple occurrences" do
      code = """
      defmodule Example do
        def foo(x) do
          case check_a(x) do
            :ok -> true
            _ -> false
          end
        end

        def bar(x) do
          case check_b(x) do
            :ok -> false
            _ -> true
          end
        end
      end
      """

      assert length(check(NoCaseBooleanResult, code)) == 2
    end
  end

  describe "flags piped wildcard-last case" do
    test "simple pipe into case" do
      assert flagged?(NoCaseBooleanResult, """
             check(x)
             |> case do
               :ok -> true
               _ -> false
             end
             """)
    end

    test "pipe chain into case" do
      assert flagged?(NoCaseBooleanResult, """
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
  # NEGATIVE — must NOT flag (no safe same-answer rewrite to match?/2)
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag shapes without a safe fix" do
    test "two specific patterns (CaseClauseError vs false differ)" do
      assert clean?(NoCaseBooleanResult, """
             case result do
               :ok -> true
               :no -> false
             end
             """)
    end

    test "tuple pair, both specific" do
      assert clean?(NoCaseBooleanResult, """
             case File.read(path) do
               {:ok, _} -> true
               {:error, _} -> false
             end
             """)
    end

    test "wildcard FIRST, false then true (second clause dead → constant)" do
      assert clean?(NoCaseBooleanResult, """
             case result do
               _ -> false
               :ok -> true
             end
             """)
    end

    test "wildcard FIRST, true then false (second clause dead → constant)" do
      assert clean?(NoCaseBooleanResult, """
             case result do
               _ -> true
               :ok -> false
             end
             """)
    end

    test "bare variable pattern then wildcard (constant)" do
      assert clean?(NoCaseBooleanResult, """
             case result do
               x -> true
               _ -> false
             end
             """)
    end
  end

  describe "does not flag other legitimate case statements" do
    test "case with boolean patterns (handled by no_case_true_false)" do
      assert clean?(NoCaseBooleanResult, """
             case x > 0 do
               true -> :positive
               false -> :negative
             end
             """)
    end

    test "case with non-boolean results" do
      assert clean?(NoCaseBooleanResult, """
             case result do
               :ok -> :success
               _ -> :failure
             end
             """)
    end

    test "case with three clauses" do
      assert clean?(NoCaseBooleanResult, """
             case result do
               :ok -> true
               :error -> false
               _ -> false
             end
             """)
    end

    test "case with tuple patterns and complex bodies" do
      assert clean?(NoCaseBooleanResult, """
             case File.read(path) do
               {:ok, content} -> content
               _ -> raise "nope"
             end
             """)
    end

    test "case with single clause" do
      assert clean?(NoCaseBooleanResult, """
             case x do
               :ok -> true
             end
             """)
    end

    test "case with both same boolean result" do
      assert clean?(NoCaseBooleanResult, """
             case x do
               :ok -> true
               _ -> true
             end
             """)
    end
  end
end
