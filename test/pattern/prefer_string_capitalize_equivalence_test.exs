defmodule Credence.Pattern.PreferStringCapitalizeEquivalenceTest do
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.PreferStringCapitalize

  test "fix preserves behaviour over Unicode strings" do
    assert_equivalent_module(
      """
      defmodule CapitalizeExample do
        defp capitalize_string(""), do: ""

        defp capitalize_string(string) do
          first_char = String.first(string) |> String.upcase()
          rest = String.slice(string, 1, byte_size(string) - String.length(first_char)) |> String.downcase()
          first_char <> rest
        end

        def run(string), do: capitalize_string(string)
      end
      """,
      rule: PreferStringCapitalize,
      call: {:run, 1},
      inputs: B.unicode_strings()
    )
  end
end
