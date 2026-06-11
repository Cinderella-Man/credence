defmodule Credence.Pattern.PreferDirectStringCheckOverComplexEnumCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferDirectStringCheckOverComplexEnum

  test "flags the anti-pattern" do
    assert flagged?(PreferDirectStringCheckOverComplexEnum, """
    defmodule Solution do
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
    """)
  end

  test "leaves good code alone" do
    assert clean?(PreferDirectStringCheckOverComplexEnum, """
    defmodule Solution do
      defp validate_pattern(string, count, divisor) do
        if rem(count, divisor) == 0 do
          pattern = String.slice(string, 0, divisor)
          String.duplicate(pattern, div(count, divisor)) == string
        else
          false
        end
      end
    end
    """)
  end
end
