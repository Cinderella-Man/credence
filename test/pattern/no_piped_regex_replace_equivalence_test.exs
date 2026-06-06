defmodule Credence.Pattern.NoPipedRegexReplaceEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoPipedRegexReplace

  # Firing snippets lifted from no_piped_regex_replace_check_test.exs:
  #   defmodule M do
  #       def clean(s), do: s |> Regex.replace(~r/[^a-z]/, "")
  #     end
  #   defmodule M do
  #       def clean(s) do
  #         s
  #         |> String.downcase()
  #         |> Regex.replace(~r/[^a-z0-9]/, "")
  #       end
  #     end
  #   defmodule M do
  #       def clean(s), do: s |> Regex.replace(~r/\s+/, " ", global: true)
  #     end

  test "no_piped_regex_replace: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoPipedRegexReplace,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
