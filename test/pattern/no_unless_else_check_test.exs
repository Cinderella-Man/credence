defmodule Credence.Pattern.NoUnlessElseCheckTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoUnlessElse.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags unless with else — block form" do
    test "basic unless...else" do
      assert flagged?("""
             def run(x) do
               unless x > 0 do
                 :negative
               else
                 :positive
               end
             end
             """)
    end

    test "multi-line bodies" do
      assert flagged?("""
             def run(list) do
               unless Enum.empty?(list) do
                 first = hd(list)
                 process(first)
               else
                 log(:empty)
                 :default
               end
             end
             """)
    end

    test "complex condition with and" do
      assert flagged?("""
             def run(x, y) do
               unless x > 0 and y > 0 do
                 :invalid
               else
                 x + y
               end
             end
             """)
    end

    test "complex condition with or" do
      assert flagged?("""
             def run(x) do
               unless is_nil(x) or x == 0 do
                 compute(x)
               else
                 :fallback
               end
             end
             """)
    end

    test "inside a module" do
      assert flagged?("""
             defmodule Example do
               def run(set, value) do
                 unless MapSet.member?(set, value) do
                   :missing
                 else
                   :found
                 end
               end
             end
             """)
    end

    test "used as expression" do
      assert flagged?("""
             def run(x) do
               result = unless x, do: :falsy, else: :truthy
               result
             end
             """)
    end

    test "inline form with do/else keywords" do
      assert flagged?("""
             def run(x) do
               unless x > 0, do: :negative, else: :positive
             end
             """)
    end

    test "inside a case arm" do
      assert flagged?("""
             def run(x) do
               case x do
                 {:ok, val} ->
                   unless val == 0 do
                     val
                   else
                     :zero
                   end
                 _ -> :error
               end
             end
             """)
    end

    test "nested unless...else — flags both" do
      code = """
      def run(x, y) do
        unless x > 0 do
          unless y > 0 do
            :both_bad
          else
            :only_x_bad
          end
        else
          :x_ok
        end
      end
      """

      assert length(check(code)) == 2
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag unless without else" do
    test "bare unless block" do
      assert clean?("""
             def run(x) do
               unless x > 0 do
                 log(:negative)
               end
             end
             """)
    end

    test "bare unless inline" do
      assert clean?("""
             def run(x) do
               unless x > 0, do: log(:negative)
             end
             """)
    end
  end

  describe "does not flag if statements" do
    test "if with else" do
      assert clean?("""
             def run(x) do
               if x > 0 do
                 :positive
               else
                 :negative
               end
             end
             """)
    end

    test "if without else" do
      assert clean?("""
             def run(x) do
               if x > 0 do
                 :positive
               end
             end
             """)
    end
  end

  describe "does not flag code without unless" do
    test "plain function" do
      assert clean?("""
             defmodule M do
               def run(x), do: x * 2
             end
             """)
    end

    test "case expression" do
      assert clean?("""
             def run(x) do
               case x do
                 :a -> 1
                 :b -> 2
               end
             end
             """)
    end

    test "cond expression" do
      assert clean?("""
             def run(x) do
               cond do
                 x > 0 -> :positive
                 true -> :non_positive
               end
             end
             """)
    end
  end

  describe "fixable?/0" do
    test "reports as fixable" do
      assert Credence.Pattern.NoUnlessElse.fixable?() == true
    end
  end
end
