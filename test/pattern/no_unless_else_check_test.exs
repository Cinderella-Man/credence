defmodule Credence.Pattern.NoUnlessElseCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoUnlessElse

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags unless with else — block form" do
    test "basic unless...else" do
      assert flagged?(NoUnlessElse, """
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
      assert flagged?(NoUnlessElse, """
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
      assert flagged?(NoUnlessElse, """
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
      assert flagged?(NoUnlessElse, """
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
      assert flagged?(NoUnlessElse, """
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
      assert flagged?(NoUnlessElse, """
             def run(x) do
               result = unless x, do: :falsy, else: :truthy
               result
             end
             """)
    end

    test "inline form with do/else keywords" do
      assert flagged?(NoUnlessElse, """
             def run(x) do
               unless x > 0, do: :negative, else: :positive
             end
             """)
    end

    test "inside a case arm" do
      assert flagged?(NoUnlessElse, """
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

      assert length(check(NoUnlessElse, code)) == 2
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag unless without else" do
    test "bare unless block" do
      assert clean?(NoUnlessElse, """
             def run(x) do
               unless x > 0 do
                 log(:negative)
               end
             end
             """)
    end

    test "bare unless inline" do
      assert clean?(NoUnlessElse, """
             def run(x) do
               unless x > 0, do: log(:negative)
             end
             """)
    end
  end

  describe "does not flag if statements" do
    test "if with else" do
      assert clean?(NoUnlessElse, """
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
      assert clean?(NoUnlessElse, """
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
      assert clean?(NoUnlessElse, """
             defmodule M do
               def run(x), do: x * 2
             end
             """)
    end

    test "case expression" do
      assert clean?(NoUnlessElse, """
             def run(x) do
               case x do
                 :a -> 1
                 :b -> 2
               end
             end
             """)
    end

    test "cond expression" do
      assert clean?(NoUnlessElse, """
             def run(x) do
               cond do
                 x > 0 -> :positive
                 true -> :non_positive
               end
             end
             """)
    end
  end

  describe "does not flag a module that defines its own unless (custom DSL)" do
    test "skips the whole module when unless/3 is defined locally" do
      assert clean?(NoUnlessElse, """
             defmodule Explorer.Query do
               def unless(condition, do: do_clause) do
                 unless(condition, do: do_clause, else: nil)
               end

               def unless(condition, do: do_clause, else: else_clause) do
                 __cond__([{true, do_clause}, {condition, else_clause}])
               end
             end
             """)
    end

    test "still flags Kernel unless in a sibling module" do
      code = """
      defmodule LocalDsl do
        defmacro unless(cond, clauses), do: build(cond, clauses)
      end

      defmodule Ordinary do
        def run(x) do
          unless x > 0 do
            :a
          else
            :b
          end
        end
      end
      """

      assert length(check(NoUnlessElse, code)) == 1
    end

    test "does not flag unless after importing a custom DSL" do
      assert clean?(NoUnlessElse, """
             defmodule Query do
               import CustomDsl

               def run(x), do: unless(x, do: :dsl_a, else: :dsl_b)
             end
             """)
    end
  end
end
