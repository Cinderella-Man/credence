defmodule Credence.Pattern.NoMissingRequireLoggerEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoMissingRequireLogger

  # Firing snippets lifted from no_missing_require_logger_check_test.exs:
  #   defmodule Outer do
  #       require Logger
  #     
  #       defmodule Inner do
  #         def run do
  #           Logger.info("from inner")
  #         end
  #       end
  #     end
  #   defmodule Outer do
  #       defmodule Inner do
  #         require Logger
  #     
  #         def run do
  #           Logger.info("from inner")
  #         end
  #       end
  #     end
  #   defmodule Outer do
  #       require Logger
  #     
  #       def run do
  #         Logger.info("from outer")
  #       end
  #     
  #       defmodule Inner do
  #         def run do
  #           :ok
  #         end
  #       end
  #     end

  test "no_missing_require_logger: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoMissingRequireLogger,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
