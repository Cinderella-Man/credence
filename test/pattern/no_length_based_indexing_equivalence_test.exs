defmodule Credence.Pattern.NoLengthBasedIndexingEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). `n = length(list); Enum.at(list, n - 1)` → `List.last(list)`.
  `Enum.at(list, length(list) - 1)` is the last element; on `[]` it is
  `Enum.at(list, -1)` = `nil`, which matches `List.last([])` = `nil`. So they agree
  on every list incl. empty.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoLengthBasedIndexing

  @before """
  defmodule Bad do
    def run(list) do
      n = length(list)
      last = Enum.at(list, n - 1)
      last
    end
  end
  """

  test "Enum.at(list, length-1) → List.last preserves the last element incl. empty" do
    assert_equivalent_module(@before,
      rule: NoLengthBasedIndexing,
      call: {:run, 1},
      inputs: [[], [5], [1, 2, 3], [1, 1.0], [:a, :b, :c], Enum.to_list(1..20)]
    )
  end

  test "Enum.count rewrite preserves both traversals of a stateful enumerable" do
    original = """
    defmodule NoLengthBasedIndexingStatefulCompileWitness do
      def run(enum) do
        n = Enum.count(enum)
        Enum.at(enum, n - 1)
      end
    end

    {:ok, agent} = Agent.start_link(fn -> 0 end)

    stream =
      Stream.repeatedly(fn -> Agent.get_and_update(agent, &{&1, &1 + 1}) end)
      |> Stream.take(3)

    result = NoLengthBasedIndexingStatefulCompileWitness.run(stream)
    calls = Agent.get(agent, & &1)

    unless {result, calls} == {5, 6} do
      raise "stateful enumerable traversal changed"
    end
    """

    emitted = Credence.RuleHelpers.apply_rule_fix(NoLengthBasedIndexing, original)

    assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(original)
    assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(emitted)
  end
end
