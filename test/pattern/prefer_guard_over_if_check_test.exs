defmodule Credence.Pattern.PreferGuardOverIfCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferGuardOverIf

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags function clause with guard-eligible if/else body" do
    test "comparison operator in condition" do
      assert flagged?(PreferGuardOverIf, """
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
      assert clean?(PreferGuardOverIf, """
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
      assert flagged?(PreferGuardOverIf, """
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
      assert flagged?(PreferGuardOverIf, """
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
      assert flagged?(PreferGuardOverIf, """
             defp check(x) do
               if x > 0 or x == 0 do
                 :non_negative
               else
                 :negative
               end
             end
             """)
    end

    test "not over a comparison in condition" do
      assert flagged?(PreferGuardOverIf, """
             defp check(x) do
               if not (x > 0) do
                 :off
               else
                 :on
               end
             end
             """)
    end

    test "def (not defp) with guard-eligible if" do
      assert flagged?(PreferGuardOverIf, """
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
      assert flagged?(PreferGuardOverIf, """
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
      assert flagged?(PreferGuardOverIf, """
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
      assert flagged?(PreferGuardOverIf, """
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
      assert clean?(PreferGuardOverIf, """
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
      assert clean?(PreferGuardOverIf, """
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
      assert clean?(PreferGuardOverIf, """
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
      assert clean?(PreferGuardOverIf, """
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

  # These are guard-*shaped* but NOT safe to rewrite, so they must stay clean:
  # a guard swallows errors and demands a strict boolean, whereas `if`
  # propagates errors and accepts any truthy value.
  describe "does not flag guard-shaped but unsafe conditions" do
    test "arithmetic that can raise (rem by zero) — if raises, a guard would fall through" do
      assert clean?(PreferGuardOverIf, """
             defp classify(x, y) do
               if rem(x, y) == 0 do
                 :divisible
               else
                 :not_divisible
               end
             end
             """)
    end

    test "bare variable — `if` is truthy, a guard requires strict `true`" do
      assert clean?(PreferGuardOverIf, """
             defp check(flag) do
               if flag do
                 :on
               else
                 :off
               end
             end
             """)
    end

    test "not over a bare variable — truthiness/raise mismatch" do
      assert clean?(PreferGuardOverIf, """
             defp check(flag) do
               if not flag do
                 :off
               else
                 :on
               end
             end
             """)
    end

    test "and over a bare variable operand" do
      assert clean?(PreferGuardOverIf, """
             defp check(flag, x) do
               if flag and x > 0 do
                 :yes
               else
                 :no
               end
             end
             """)
    end

    test "length builtin can raise on a non-list" do
      assert clean?(PreferGuardOverIf, """
             defp check(x) do
               if length(x) > 0 do
                 :non_empty
               else
                 :empty
               end
             end
             """)
    end
  end

  describe "does not flag when if is not the sole body expression" do
    test "if after assignment" do
      assert clean?(PreferGuardOverIf, """
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
      assert clean?(PreferGuardOverIf, """
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
      assert clean?(PreferGuardOverIf, """
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
      assert clean?(PreferGuardOverIf, """
             if System.get_env("DEBUG") do
               Logger.debug("enabled")
             else
               Logger.info("disabled")
             end
             """)
    end

    test "if/else inside case clause" do
      assert clean?(PreferGuardOverIf, """
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
      assert clean?(PreferGuardOverIf, """
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
      assert clean?(PreferGuardOverIf, """
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

  describe "does not flag function with non-if body" do
    test "simple expression body" do
      assert clean?(PreferGuardOverIf, "defp double(x), do: x * 2")
    end

    test "case in body" do
      assert clean?(PreferGuardOverIf, """
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
