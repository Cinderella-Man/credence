defmodule Credence.Pattern.NoTrivialDelegationEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). The fix deletes a trivial `defp` and inlines its body
  at the call site — a whole-module rewrite, so behaviour is observable only by
  compiling the before/after module and calling the surviving function.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoTrivialDelegation

  @before """
  defmodule Bad do
    defp string_length(str), do: String.length(str)
    def run(s), do: string_length(s)
  end
  """

  test "inlining a trivial delegate preserves run/1 behaviour" do
    assert_equivalent_module(@before,
      rule: NoTrivialDelegation,
      call: {:run, 1},
      inputs: ["", "a", "abc", "héllo", "日本語"]
    )
  end
end
