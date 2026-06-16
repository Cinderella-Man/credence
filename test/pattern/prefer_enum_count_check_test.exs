defmodule Credence.Pattern.PreferEnumCountCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferEnumCount

  describe "flags the anti-pattern" do
    test "flags piped Enum.reduce with counting if-body" do
      code = """
      values
      |> Enum.reduce(0, fn count, odd_count ->
        if rem(count, 2) == 1, do: odd_count + 1, else: odd_count
      end)
      """

      issues = check(PreferEnumCount, code)

      assert length(issues) == 1
      assert hd(issues).rule == :prefer_enum_count
    end

    test "flags non-piped Enum.reduce with counting if-body" do
      code = """
      Enum.reduce(list, 0, fn x, acc ->
        if x > 5, do: acc + 1, else: acc
      end)
      """

      issues = check(PreferEnumCount, code)

      assert length(issues) == 1
      assert hd(issues).rule == :prefer_enum_count
    end

    test "flags reversed operand order (1 + acc)" do
      code = """
      Enum.reduce(list, 0, fn x, acc ->
        if rem(x, 3) == 0, do: 1 + acc, else: acc
      end)
      """

      issues = check(PreferEnumCount, code)

      assert length(issues) == 1
      assert hd(issues).rule == :prefer_enum_count
    end

    test "flags multiple counting reduces" do
      code = """
      defmodule M do
        def process(a, b) do
          x = Enum.reduce(a, 0, fn v, acc -> if v > 0, do: acc + 1, else: acc end)
          y = Enum.reduce(b, 0, fn v, acc -> if rem(v, 2) == 0, do: acc + 1, else: acc end)
          {x, y}
        end
      end
      """

      issues = check(PreferEnumCount, code)

      assert length(issues) == 2
    end
  end

  describe "leaves good code alone" do
    test "passes code that already uses Enum.count/2" do
      code = "Enum.count(values, &(rem(&1, 2) == 1))"

      assert clean?(PreferEnumCount, code)
    end

    test "does NOT flag sum-reduction pattern" do
      code = "Enum.reduce(list, 0, fn x, acc -> acc + x end)"

      assert clean?(PreferEnumCount, code)
    end

    test "does NOT flag reduce with non-zero initial accumulator" do
      code = """
      Enum.reduce(list, 1, fn x, acc ->
        if x > 0, do: acc + 1, else: acc
      end)
      """

      assert clean?(PreferEnumCount, code)
    end

    test "does NOT flag reduce with non-identity else branch" do
      code = """
      Enum.reduce(list, 0, fn x, acc ->
        if x > 0, do: acc + 1, else: acc - 1
      end)
      """

      assert clean?(PreferEnumCount, code)
    end

    test "does NOT flag reduce with increment > 1" do
      code = """
      Enum.reduce(list, 0, fn x, acc ->
        if x > 0, do: acc + 2, else: acc
      end)
      """

      assert clean?(PreferEnumCount, code)
    end

    test "does NOT flag reduce with map-based accumulation" do
      code = """
      Enum.reduce(list, %{}, fn x, acc ->
        Map.put(acc, x, true)
      end)
      """

      assert clean?(PreferEnumCount, code)
    end

    # The condition references the accumulator, so it depends on the running
    # count (here it caps at 3): Enum.count/2 can't express that, and the
    # rewritten `acc` would be unbound. Not the same answer — skip it.
    test "does NOT flag reduce whose condition references the accumulator" do
      code = """
      Enum.reduce(list, 0, fn x, acc ->
        if acc < 3, do: acc + 1, else: acc
      end)
      """

      assert clean?(PreferEnumCount, code)
    end

    # The condition never references the element, so the capture would have no
    # `&1` ("invalid args for &" — a compile error). Skip it.
    test "does NOT flag reduce whose condition ignores the element" do
      code = """
      Enum.reduce(list, 0, fn x, acc ->
        if flag, do: acc + 1, else: acc
      end)
      """

      assert clean?(PreferEnumCount, code)
    end

    # The condition already contains a `&` capture; wrapping it in another
    # `&(...)` would be a nested capture ("nested captures are not allowed").
    test "does NOT flag reduce whose condition contains a capture" do
      code = """
      Enum.reduce(list, 0, fn x, acc ->
        if Enum.any?(others, &(&1 == x)), do: acc + 1, else: acc
      end)
      """

      assert clean?(PreferEnumCount, code)
    end
  end
end
