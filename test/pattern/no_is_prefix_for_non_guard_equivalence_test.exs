defmodule Credence.Pattern.NoIsPrefixForNonGuardEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoIsPrefixForNonGuard

  # Firing snippets lifted from no_is_prefix_for_non_guard_check_test.exs:
  #   defmodule Bad do
  #       def is_palindrome(str), do: str == String.reverse(str)
  #     end
  #   defmodule Bad do
  #       defp is_palindrome(list), do: list == Enum.reverse(list)
  #     end
  #   defmodule Bad do
  #       def is_valid_ipv4(ip) when is_binary(ip) do
  #         parts = String.split(ip, ".")
  #         length(parts) == 4
  #       end
  #     end

  test "no_is_prefix_for_non_guard: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoIsPrefixForNonGuard,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
