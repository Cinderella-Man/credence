defmodule Credence.Pattern.NoTrailingNewlineInDocEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call, doc-observation) — compare `Code.fetch_docs/1` of before/after.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoTrailingNewlineInDoc

  # Firing snippets lifted from no_trailing_newline_in_doc_check_test.exs:
  #   defmodule Example do
  #       @doc "Finds the missing number.\n"
  #       def missing_number(list), do: 0
  #     end
  #   defmodule Example do
  #       @moduledoc "A module for palindrome checking.\n"
  #       def palindrome?(s), do: s == String.reverse(s)
  #     end
  #   defmodule Example do
  #       @typedoc "A custom type.\n"
  #       @type t :: :ok | :error
  #     end

  test "no_trailing_newline_in_doc: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoTrailingNewlineInDoc,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
