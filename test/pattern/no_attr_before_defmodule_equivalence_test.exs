defmodule Credence.Pattern.NoAttrBeforeDefmoduleEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoAttrBeforeDefmodule

  # Firing snippets lifted from no_attr_before_defmodule_check_test.exs:
  #   @moduledoc "some doc"
  #     defmodule Foo do
  #       def bar, do: :ok
  #     end
  #   @moduledoc "m"
  #     @doc "f"
  #     @spec foo() :: :ok
  #     defmodule Foo do
  #       def foo, do: :ok
  #     end
  #   @moduledoc """
  #     Some doc
  #     """
  #     defmodule Foo do
  #       def bar, do: :ok
  #     end

  test "no_attr_before_defmodule: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoAttrBeforeDefmodule,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
