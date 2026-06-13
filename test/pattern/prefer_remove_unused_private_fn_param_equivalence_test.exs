defmodule Credence.Pattern.PreferRemoveUnusedPrivateFnParamEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). A private function with an unused `_table` parameter
  is rewritten to remove that parameter and its argument at every call site.
  The public entry point's behaviour must be identical for every input.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferRemoveUnusedPrivateFnParam

  @before """
  defmodule BadLCS do
    def find_lcs_length(first, second) do
      compute_lcs(String.to_charlist(first), String.to_charlist(second), nil)
    end

    defp compute_lcs(chars_first, chars_second, _table)
         when chars_first != [] and chars_second != [] do
      first_char = hd(chars_first)
      rest_first = tl(chars_first)
      second_char = hd(chars_second)
      rest_second = tl(chars_second)

      if first_char == second_char do
        sub_lcs = compute_lcs(rest_first, rest_second, nil)
        sub_lcs + 1
      else
        lcs_without_first = compute_lcs(rest_first, chars_second, nil)
        lcs_without_second = compute_lcs(chars_first, rest_second, nil)
        max(lcs_without_first, lcs_without_second)
      end
    end

    defp compute_lcs([], _second, _table), do: 0
    defp compute_lcs(_first, [], _table), do: 0
  end
  """

  test "removing unused _table param preserves LCS behaviour" do
    assert_equivalent_module(@before,
      rule: PreferRemoveUnusedPrivateFnParam,
      call: {:find_lcs_length, 2},
      inputs: [
        {"", ""},
        {"abc", ""},
        {"", "abc"},
        {"abc", "abc"},
        {"abc", "def"},
        {"abcdef", "acf"},
        {"AGGTAB", "GXTXAYB"}
      ]
    )
  end
end
