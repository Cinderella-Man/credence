defmodule Credence.Pattern.PreferPatternMatchingForEmptyStringEquivalenceTest do
  @moduledoc """
  Tier 2 (module). Under the `single_codepoint_graphemes` assumption,
  `if String.trim(var) == "" do [] else <body> end` and the rewrite
  `def func(""), do: []` + `def func(var) do <body> end` agree because
  for single-codepoint strings without leading/trailing whitespace,
  `String.trim(var) == ""` is equivalent to `var == ""`.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferPatternMatchingForEmptyString

  test "fix preserves behaviour" do
    assert_equivalent_module(
      """
      defmodule Solution do
        def comma_separated_to_list(input_string) do
          if String.trim(input_string) == "" do
            []
          else
            String.split(input_string, ",")
            |> Enum.map(&String.to_integer/1)
          end
        end
      end
      """,
      rule: PreferPatternMatchingForEmptyString,
      call: {:comma_separated_to_list, 1},
      inputs: ["", "1,2,3", "42"]
    )
  end
end
