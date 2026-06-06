defmodule Credence.Pattern.NoCaseDestructureInPipeEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). A pipeline ending in `|> case do value -> ... end` (a single
  catch-all clause used only to bind/transform) is rewritten to the equivalent
  pipe-friendly form. The single clause binds the piped value and computes the same
  result, so behaviour is preserved.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoCaseDestructureInPipe

  @before """
  defmodule Bad do
    def process(x) do
      x
      |> compute()
      |> case do
        value -> value + 1
      end
    end
    defp compute(x), do: x * 10
  end
  """

  test "pipe into single-clause case → preserves the computed value" do
    assert_equivalent_module(@before,
      rule: NoCaseDestructureInPipe,
      call: {:process, 1},
      inputs: [0, 1, 2, -3, 100]
    )
  end
end
