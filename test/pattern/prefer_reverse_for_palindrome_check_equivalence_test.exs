defmodule Credence.Pattern.PreferReverseForPalindromeCheckEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). Replaces index-based recursive palindrome check with
  `list == Enum.reverse(list)`.

  The before/after code both return a boolean for every list input, so
  behaviour-preservation is straightforward. Inputs cover:
    * empty list (always palindrome)
    * single element (always palindrome)
    * small palindromes and non-palindromes
    * larger lists
    * value-kind (integers vs atoms)
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferReverseForPalindromeCheck

  test "index-based recursion -> Enum.reverse preserves behaviour for all lists" do
    assert_equivalent_module(
      """
      defmodule Solution do
        def palindrome_check(list) do
          palindrome_helper?(list, 0, length(list) - 1)
        end

        defp palindrome_helper?(_list, left_index, right_index) when left_index >= right_index do
          true
        end

        defp palindrome_helper?(list, left_index, right_index) do
          left_char = Enum.at(list, left_index)
          right_char = Enum.at(list, right_index)

          if left_char == right_char do
            palindrome_helper?(list, left_index + 1, right_index - 1)
          else
            false
          end
        end
      end
      """,
      rule: PreferReverseForPalindromeCheck,
      call: {:palindrome_check, 1},
      inputs: [
        [],
        [1],
        [1, 2, 1],
        [1, 2, 3],
        [1, 2, 3, 2, 1],
        [1, 2, 3, 1],
        [:a, :b, :a],
        [:a, :b, :c],
        Enum.to_list(1..50),
        Enum.to_list(1..50) |> Enum.reverse()
      ]
    )
  end
end
