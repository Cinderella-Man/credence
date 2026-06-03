defmodule Credence.AssumptionsMetaTest do
  @moduledoc """
  Whole-suite teeth for the safety story (decisions 11 and 18). These turn two
  silent holes into red builds:

    * a rule tagging a switch that does not exist (a rule-side typo), and
    * a rule that needs a promise but ships without a property test proving it.
  """
  use ExUnit.Case

  alias Credence.Assumptions

  @rules Credence.Pattern.default_rules()

  test "every rule's assumptions/0 names only known switches (decision 11)" do
    known = Assumptions.names()
    bad = for r <- @rules, a <- r.assumptions(), a not in known, do: {r, a}

    assert bad == [],
           "rules naming unknown switches (⊄ Assumptions.names()): #{inspect(bad)}"
  end

  test "every rule with a non-empty assumptions/0 has a property test file (decision 18)" do
    missing =
      for r <- @rules, r.assumptions() != [] do
        snake = r |> Module.split() |> List.last() |> Macro.underscore()
        {r, "test/pattern/#{snake}_property_test.exs"}
      end
      |> Enum.reject(fn {_r, path} -> File.exists?(path) end)
      |> Enum.map(fn {r, path} -> "#{inspect(r)} → expected #{path}" end)

    assert missing == [],
           "switched rules without a property test file:\n  " <> Enum.join(missing, "\n  ")
  end
end
