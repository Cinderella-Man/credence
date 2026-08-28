defmodule Credence.Pattern.PreferComprehensionForFilteredRangeFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferComprehensionForFilteredRange

  describe "rewrites the anti-pattern" do
    test "piped reduce |> reverse becomes for comprehension" do
      input = """
      defmodule Solution do
        def findmissingnumbers(numbers) do
          n = length(numbers)
          present = MapSet.new(numbers)

          Enum.reduce(1..n, [], fn num, missing ->
            if MapSet.member?(present, num), do: missing, else: [num | missing]
          end)
          |> Enum.reverse()
        end
      end
      """

      result = fix(PreferComprehensionForFilteredRange, input)

      # Verify the fix compiles and produces a for comprehension
      assert valid_syntax?(result)

      confirm_fix(fix(PreferComprehensionForFilteredRange, input), """
      defmodule Solution do
        def findmissingnumbers(numbers) do
          n = length(numbers)
          present = MapSet.new(numbers)

          for num <- 1..n, !MapSet.member?(present, num), do: num
        end
      end
      """)
    end

    test "direct Enum.reverse(Enum.reduce(...)) form is rewritten" do
      input = """
      Enum.reverse(Enum.reduce(1..n, [], fn num, acc ->
        if MapSet.member?(set, num), do: acc, else: [num | acc]
      end))
      """

      result = fix(PreferComprehensionForFilteredRange, input)

      assert valid_syntax?(result)

      confirm_fix(
        fix(PreferComprehensionForFilteredRange, input),
        "for num <- 1..n, !MapSet.member?(set, num), do: num"
      )
    end

    test "explicit-step range carries through to the comprehension" do
      input = """
      Enum.reduce(1..n//1, [], fn num, acc ->
        if MapSet.member?(set, num), do: acc, else: [num | acc]
      end)
      |> Enum.reverse()
      """

      result = fix(PreferComprehensionForFilteredRange, input)

      assert valid_syntax?(result)

      confirm_fix(
        fix(PreferComprehensionForFilteredRange, input),
        "for num <- 1..n//1, !MapSet.member?(set, num), do: num"
      )
    end

    test "condition with a low-precedence operator is parenthesized under !" do
      input = """
      Enum.reduce(1..n, [], fn num, acc ->
        if num == skip, do: acc, else: [num | acc]
      end)
      |> Enum.reverse()
      """

      result = fix(PreferComprehensionForFilteredRange, input)

      assert valid_syntax?(result)

      confirm_fix(result, "for num <- 1..n, !(num == skip), do: num")
    end

    test "preserves a comment attached to the removed if expression" do
      input = """
      Enum.reduce(1..n, [], fn num, acc ->
        # keep this explanation
        if rem(num, 2) == 0, do: acc, else: [num | acc]
      end)
      |> Enum.reverse()
      """

      confirm_fix(
        fix(PreferComprehensionForFilteredRange, input),
        """
        # keep this explanation
        for num <- 1..n, !(rem(num, 2) == 0), do: num
        """
      )
    end

    test "does not rewrite calls through a shadowing Enum alias" do
      input = """
      defmodule PreferComprehensionFixAliasProbe do
        alias MyEnum, as: Enum

        def run(n) do
          Enum.reduce(1..n, [], fn num, acc ->
            if rem(num, 2) == 0, do: acc, else: [num | acc]
          end)
          |> Enum.reverse()
        end
      end
      """

      confirm_fix(fix(PreferComprehensionForFilteredRange, input), input)
    end

    test "non-matching code is left unchanged" do
      code = "for num <- 1..n, !MapSet.member?(present, num), do: num"

      confirm_fix(fix(PreferComprehensionForFilteredRange, code), code)
    end
  end

  describe "round-trip: fixed code has no further issues" do
    test "fixed code is clean" do
      code = """
      defmodule Solution do
        def findmissingnumbers(numbers) do
          n = length(numbers)
          present = MapSet.new(numbers)

          Enum.reduce(1..n, [], fn num, missing ->
            if MapSet.member?(present, num), do: missing, else: [num | missing]
          end)
          |> Enum.reverse()
        end
      end
      """

      assert check(
               PreferComprehensionForFilteredRange,
               fix(PreferComprehensionForFilteredRange, code)
             ) == []
    end
  end
end
