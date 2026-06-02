defmodule Credence.Pattern.PreferGuardOverIfCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.PreferGuardOverIf

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    PreferGuardOverIf.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags function clause with guard-eligible if/else body" do
    test "comparison operator in condition" do
      assert flagged?("""
             defp accumulate_run(last_val, [head | tail] = list, current_run) do
               if head > last_val do
                 accumulate_run(head, tail, [head | current_run])
               else
                 {Enum.reverse(current_run), list}
               end
             end
             """)
    end

    test "equality check in condition is not flagged (prefer pattern matching)" do
      assert clean?("""
             defp handle(x, acc) do
               if x == 0 do
                 acc
               else
                 [x | acc]
               end
             end
             """)
    end

    test "is_nil guard in condition" do
      assert flagged?("""
             defp process(val, default) do
               if is_nil(val) do
                 default
               else
                 val
               end
             end
             """)
    end

    test "compound guard condition with and" do
      assert flagged?("""
             defp check(x, y) do
               if x > 0 and y > 0 do
                 :both_positive
               else
                 :not_both
               end
             end
             """)
    end

    test "compound guard condition with or" do
      assert flagged?("""
             defp check(x) do
               if x > 0 or x == 0 do
                 :non_negative
               else
                 :negative
               end
             end
             """)
    end

    test "not operator in condition" do
      assert flagged?("""
             defp check(flag) do
               if not flag do
                 :off
               else
                 :on
               end
             end
             """)
    end

    test "arithmetic in condition" do
      assert flagged?("""
             defp classify(x, y) do
               if rem(x, y) == 0 do
                 :divisible
               else
                 :not_divisible
               end
             end
             """)
    end

    test "def (not defp) with guard-eligible if" do
      assert flagged?("""
             def process(x) do
               if x > 0 do
                 :positive
               else
                 :non_positive
               end
             end
             """)
    end

    test "function with existing guard and if body" do
      assert flagged?("""
             defp run(x) when is_integer(x) do
               if x > 0 do
                 :positive
               else
                 :non_positive
               end
             end
             """)
    end

    test "multi-clause function with guardable if in one clause" do
      assert flagged?("""
             defp run([], acc), do: acc
             defp run([h | t], acc) do
               if h > 0 do
                 run(t, [h | acc])
               else
                 run(t, acc)
               end
             end
             """)
    end

    test "if/else with keyword syntax" do
      assert flagged?("""
             defp check(x) do
               if x > 0, do: :positive, else: :non_positive
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag if without else" do
    test "if without else branch" do
      assert clean?("""
             defp run(x) do
               if x > 0 do
                 IO.puts("positive")
               end
             end
             """)
    end
  end

  describe "does not flag if with non-guard-eligible condition" do
    test "function call in condition" do
      assert clean?("""
             defp process(data) do
               if valid?(data) do
                 transform(data)
               else
                 {:error, :invalid}
               end
             end
             """)
    end

    test "remote function call in condition" do
      assert clean?("""
             defp process(list) do
               if Enum.empty?(list) do
                 :empty
               else
                 hd(list)
               end
             end
             """)
    end

    test "String.contains? in condition" do
      assert clean?("""
             defp check(str) do
               if String.contains?(str, "foo") do
                 :found
               else
                 :not_found
               end
             end
             """)
    end
  end

  describe "does not flag when if is not the sole body expression" do
    test "if after assignment" do
      assert clean?("""
             defp run(x) do
               result = compute(x)
               if result > 0 do
                 :positive
               else
                 :non_positive
               end
             end
             """)
    end

    test "if inside a pipeline" do
      assert clean?("""
             defp run(x) do
               x
               |> transform()
               |> then(fn val ->
                 if val > 0 do
                   :positive
                 else
                   :non_positive
                 end
               end)
             end
             """)
    end

    test "if as part of a block with multiple expressions" do
      assert clean?("""
             defp run(x) do
               log(x)
               if x > 0 do
                 :positive
               else
                 :non_positive
               end
             end
             """)
    end
  end

  describe "does not flag non-function constructs" do
    test "standalone if/else in module body" do
      assert clean?("""
             if System.get_env("DEBUG") do
               Logger.debug("enabled")
             else
               Logger.info("disabled")
             end
             """)
    end

    test "if/else inside case clause" do
      assert clean?("""
             defp run(x) do
               case x do
                 {:ok, val} ->
                   if val > 0 do
                     :positive
                   else
                     :non_positive
                   end
                 _ -> :error
               end
             end
             """)
    end

    test "cond expression" do
      assert clean?("""
             defp run(x) do
               cond do
                 x > 0 -> :positive
                 x == 0 -> :zero
                 true -> :negative
               end
             end
             """)
    end

    test "case expression" do
      assert clean?("""
             defp run(x) do
               case x do
                 0 -> :zero
                 n when n > 0 -> :positive
                 _ -> :negative
               end
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # AUTO-FIX
  # ═══════════════════════════════════════════════════════════════════

  describe "auto-fixes if/else into two function clauses" do
    defp apply_fix(code) do
      Credence.RuleHelpers.apply_rule_fix(PreferGuardOverIf, code)
    end

    test "comparison operator" do
      source = """
      defp check(x) do
        if x > 0 do
          :positive
        else
          :non_positive
        end
      end
      """

      fixed = apply_fix(source)
      assert fixed =~ "when x > 0"
      assert fixed =~ ":positive"
      assert fixed =~ ":non_positive"
      refute fixed =~ "if x > 0"
    end

    test "equality check is not fixed (prefer pattern matching)" do
      source = """
      defp check(x) do
        if x == 0 do
          :zero
        else
          :non_zero
        end
      end
      """

      assert apply_fix(source) == source
    end

    test "is_nil guard" do
      source = """
      defp check(val, default) do
        if is_nil(val) do
          default
        else
          val
        end
      end
      """

      fixed = apply_fix(source)
      assert fixed =~ "when is_nil(val)"
      assert fixed =~ "default"
    end

    test "preserves existing guard" do
      source = """
      defp check(x) when is_integer(x) do
        if x > 0 do
          :positive
        else
          :non_positive
        end
      end
      """

      fixed = apply_fix(source)
      assert fixed =~ "when is_integer(x) and x > 0"
      assert fixed =~ ":non_positive"
    end

    test "keyword syntax if" do
      source = """
      defp check(x) do
        if x > 0, do: :positive, else: :non_positive
      end
      """

      fixed = apply_fix(source)
      assert fixed =~ "when x > 0"
      assert fixed =~ ":positive"
      assert fixed =~ ":non_positive"
    end

    test "underscores unused params in catch-all clause" do
      source = """
      defp find_position(matrix, target, low, high) do
        if low <= high do
          do_search(matrix, target, low, high)
        else
          false
        end
      end
      """

      fixed = apply_fix(source)
      assert fixed =~ "when low <= high"
      # Catch-all clause: all params unused since body is just `false`
      assert fixed =~ "defp find_position(_matrix, _target, _low, _high)"
    end

    test "underscores unused param in first clause when not used in body or guard" do
      source = """
      defp classify(x, y) do
        if x > 0 do
          :positive
        else
          y
        end
      end
      """

      fixed = apply_fix(source)
      # First clause: x used in guard, y not used anywhere -> _y
      assert fixed =~ "defp classify(x, _y) when x > 0"
      # Second clause: x not used, y used in body
      assert fixed =~ "defp classify(_x, y)"
    end

    test "does not fix non-guard-eligible condition" do
      source = """
      defp check(x) do
        if valid?(x) do
          :ok
        else
          :error
        end
      end
      """

      assert apply_fix(source) == source
    end

    test "does not fix remote function call in condition" do
      source = """
      defp check(list) do
        if Enum.empty?(list) do
          :empty
        else
          hd(list)
        end
      end
      """

      assert apply_fix(source) == source
    end
  end

  describe "does not flag function with non-if body" do
    test "simple expression body" do
      assert clean?("""
             defp double(x), do: x * 2
             """)
    end

    test "case in body" do
      assert clean?("""
             defp run(x) do
               case x do
                 :a -> 1
                 :b -> 2
               end
             end
             """)
    end
  end
end
