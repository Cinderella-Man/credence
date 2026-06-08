defmodule Credence.AssumptionGeneratorsTest do
  @moduledoc """
  Honesty check for the shared generators. A broken character range would make
  every property test pass while proving nothing, so we assert the generator
  really only produces promise-satisfying strings.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Credence.AssumptionGenerators

  property "single_codepoint_string/0 only produces single-codepoint graphemes" do
    check all(s <- AssumptionGenerators.single_codepoint_string()) do
      # Every grapheme must be exactly one codepoint — the promise, by construction.
      assert Enum.all?(String.graphemes(s), fn g -> length(String.to_charlist(g)) == 1 end)
    end
  end
end
