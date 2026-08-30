defmodule Credence.Pattern.NoIfEmptyForEnumMinMaxEquivalenceTest do
  @moduledoc """
  Tier 1 (expression).
  `if Enum.empty?(x), do: default, else: Enum.min(x)` → an explicit `case`.
  The rewrite preserves the original separate emptiness check and min traversal.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoIfEmptyForEnumMinMax
  alias Credence.RuleHelpers

  test "if Enum.empty? default else Enum.min → explicit case incl. empty" do
    assert_equivalent(
      "if Enum.empty?(lengths), do: 0, else: Enum.min(lengths)",
      rule: NoIfEmptyForEnumMinMax,
      vars: [:lengths],
      inputs: [[], [3, 1, 2], [5], [1, 1.0, 2], [-3, -1]]
    )
  end

  test "the emitted fix preserves separate traversals of a stateful enumerable" do
    source = """
    defmodule StatefulBeforeNIEFEMM do
      def run do
        {:ok, counter} = Agent.start_link(fn -> 0 end)

        values =
          Stream.resource(
            fn -> Agent.get_and_update(counter, fn n -> {n, n + 1} end) end,
            fn
              0 -> {[10], :done}
              1 -> {[1], :done}
              :done -> {:halt, :done}
            end,
            fn _ -> :ok end
          )

        result = if Enum.empty?(values), do: 0, else: Enum.min(values)
        Agent.stop(counter)
        result
      end
    end
    """

    emitted = Credence.RuleCase.fix(NoIfEmptyForEnumMinMax, source)
    emitted = String.replace(emitted, "StatefulBeforeNIEFEMM", "StatefulAfterNIEFEMM")

    witness =
      source <>
        emitted <>
        """
        unless StatefulBeforeNIEFEMM.run() == StatefulAfterNIEFEMM.run() do
          raise "stateful enumerable result changed"
        end
        """

    assert {:ok, []} = RuleHelpers.compile_and_capture(witness)
  end
end
