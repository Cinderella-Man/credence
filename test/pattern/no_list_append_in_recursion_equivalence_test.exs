defmodule Credence.Pattern.NoListAppendInRecursionEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoListAppendInRecursion

  # Firing snippets lifted from no_list_append_in_recursion_check_test.exs:
  #   defmodule Bad do
  #       def build([h | t], result) do
  #         build(t, result ++ [h * 2])
  #       end
  #     
  #       def build([], result), do: result
  #     end
  #   defmodule Bad do
  #       defp helper([h | t], acc) when is_integer(h) do
  #         helper(t, acc ++ [h])
  #       end
  #     
  #       defp helper([], acc), do: acc
  #     end
  #   defmodule Bad do
  #       def collect([h | t], acc) do
  #         collect(t, acc ++ [String.upcase(h)])
  #       end
  #     
  #       def collect([], acc), do: acc
  #     end

  test "no_list_append_in_recursion: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoListAppendInRecursion,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
