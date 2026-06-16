defmodule Credence.Pattern.PreferGuardOverIfEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). An `if cond do … else … end` that is a function's whole
  body becomes two guarded clauses. Safe only when `cond` is a non-raising,
  guard-legal test — the rule is narrowed to that core: it does NOT fire when the
  condition contains a call that could raise (verified: `if hd(x) > 0` is left
  alone), so moving it into a guard can't swallow an error or change a truthiness.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferGuardOverIf

  @before """
  defmodule Bad do
    def run(x), do: f(x)
    defp f(x) do
      if x > 0 do
        :pos
      else
        :nonpos
      end
    end
  end
  """

  test "if (guard-legal cond) body → guarded clauses preserve dispatch" do
    assert_equivalent_module(@before,
      rule: PreferGuardOverIf,
      call: {:run, 1},
      inputs: [1, -1, 0, 100, -50]
    )
  end

  @var_eq_before """
  defmodule Compress do
    def process([], _index, result, current_char, count) do
      result <> Integer.to_string(count)
    end

    def process([current_char | rest], index, result, prev_char, count) do
      if current_char == prev_char do
        process(rest, index + 1, result, prev_char, count + 1)
      else
        new_result = result <> prev_char <> Integer.to_string(count)
        process(rest, index + 1, new_result, current_char, 1)
      end
    end
  end
  """

  test "var == var equality body → guarded clauses preserve dispatch" do
    assert_equivalent_module(@var_eq_before,
      rule: PreferGuardOverIf,
      call: {:process, 5},
      inputs: [
        [~c"aaabbb", 0, "", ?a, 3],
        [~c"aabb", 0, "", ?a, 2],
        [~c"ab", 0, "", ?a, 1],
        [~c"bba", 0, "a3", ?b, 2],
        [~c"a", 0, "", ?a, 1]
      ]
    )
  end
end
