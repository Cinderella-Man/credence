defmodule Credence.Pattern.PreferIntegerToBinaryForBitLengthEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) behaviour equivalence.

  The fix replaces `floor(:math.log(n) / :math.log(2)) + 1` with
  `n |> :erlang.integer_to_binary(2) |> String.length()` and adds a
  negative-integer clause. Both implementations agree on every non-negative
  integer, and the module adds `num_of_bits(-n)` forwarding for negatives.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence

  alias Credence.Pattern.PreferIntegerToBinaryForBitLength

  @before_module """
  defmodule BitLengthBefore do
    @spec num_of_bits(non_neg_integer()) :: non_neg_integer()
    def num_of_bits(0), do: 0

    def num_of_bits(n) when n > 0 do
      floor(:math.log(n) / :math.log(2)) + 1
    end
  end
  """

  test "fix preserves behaviour for non-negative integers" do
    assert_equivalent_module(
      @before_module,
      rule: PreferIntegerToBinaryForBitLength,
      call: {:num_of_bits, 1},
      inputs: [1, 2, 3, 4, 7, 8, 15, 16, 255, 256, 1024]
    )
  end
end
