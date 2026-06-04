defmodule Credence.Pattern.NoTautologicalIfCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoTautologicalIf

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoTautologicalIf.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags if/else with identical branches" do
    test "simple variable in both branches" do
      assert flagged?("""
             defp do_pass(list) do
               {swapped, result} = do_pass_recursive(list, false, [])
               if swapped do
                 result
               else
                 result
               end
             end
             """)
    end

    test "function call in both branches" do
      assert flagged?("""
             def check(x) do
               if x > 0 do
                 process(x)
               else
                 process(x)
               end
             end
             """)
    end

    test "inline form" do
      assert flagged?("""
             def check(x) do
               if x > 0, do: value, else: value
             end
             """)
    end

    test "nested expression in both branches" do
      assert flagged?("""
             def check(x) do
               if condition do
                 Enum.map(list, fn i -> i + 1 end)
               else
                 Enum.map(list, fn i -> i + 1 end)
               end
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag" do
    test "different branches" do
      assert clean?("""
             def check(x) do
               if x > 0 do
                 x
               else
                 0
               end
             end
             """)
    end

    test "if without else" do
      assert clean?("""
             def check(x) do
               if x > 0 do
                 IO.puts("positive")
               end
             end
             """)
    end

    test "boolean branches (handled by no_if_true_false)" do
      assert clean?("""
             def check(x) do
               if x > 0 do
                 true
               else
                 false
               end
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — deliberately skipped because the fix would change behaviour
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag (unsafe to fix — narrowed out)" do
    test "side-effecting condition: dropping it would skip the call" do
      assert clean?("""
             def check(x) do
               if launch_missiles() do
                 :ok
               else
                 :ok
               end
             end
             """)
    end

    test "condition that may raise: dropping it would skip the exception" do
      assert clean?("""
             def check(x) do
               if hd(x) do
                 :ok
               else
                 :ok
               end
             end
             """)
    end

    test "binding condition: dropping it would lose the assignment" do
      assert clean?("""
             def check(x) do
               if (y = compute(x)) do
                 y
               else
                 y
               end
             end
             """)
    end

    test "comparison with impure operand is not pure" do
      assert clean?("""
             def check(x) do
               if size(x) > 0 do
                 :ok
               else
                 :ok
               end
             end
             """)
    end

    test "body binds a variable that could shadow an outer one" do
      assert clean?("""
             def check(x) do
               if flag do
                 y = compute(x)
                 y
               else
                 y = compute(x)
                 y
               end
             end
             """)
    end
  end
end
