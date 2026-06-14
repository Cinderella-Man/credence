defmodule Credence.Pattern.PreferDirectStringCheckOverComplexEnumEquivalenceTest do
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferDirectStringCheckOverComplexEnum

  test "fix preserves behaviour" do
    assert_equivalent_module(
      """
      defmodule Solution do
        def smallest_divisor(string, count) when count >= 1 do
          case count do
            1 ->
              1

            n ->
              2..div(n, 2)//1
              |> Enum.find(1, fn divisor ->
                validate_pattern(string, n, divisor)
              end)
          end
        end

        defp validate_pattern(string, count, divisor) do
          repeat_count = div(count, divisor)

          if Integer.mod(count, divisor) == 0 do
            pattern = String.slice(string, 0, divisor)
            Enum.all?(0..(repeat_count - 1), fn i ->
              start = i * divisor
              String.slice(string, start, count - start) == pattern and (start + count == count or String.slice(string, start + divisor, count) != pattern)
            end)
            # More straightforward check:
            full_pattern = String.duplicate(pattern, repeat_count)
            string == full_pattern
          else
            false
          end
        end
      end
      """,
      rule: PreferDirectStringCheckOverComplexEnum,
      call: {:smallest_divisor, 2},
      inputs: [
        {"abcabc", 6},
        {"aaaa", 4},
        {"abc", 3},
        {"ab", 2},
        {"hello", 5},
        {"a", 1},
        {"abab", 4},
        {"aaa", 3},
        {"abcabcabc", 9}
      ]
    )
  end
end
