defmodule Credence.EquivalenceMetaTest do
  @moduledoc """
  The behaviour-equivalence GATE.

  Enforces — for every discovered `Credence.Pattern.Rule` — that a behaviour-
  equivalence test exists and is about that rule, and that no equivalence test is
  still an un-filled skeleton. With the `:equivalence_todo` exclude removed from
  `test_helper.exs`, a newly-added rule that ships without a (non-skeleton)
  equivalence test now fails the suite, so the backfill cannot silently regress.

  Coverage is checked by *module name*: each rule's test must be
  `defmodule Credence.Pattern.<RuleShortName>EquivalenceTest`. This avoids guessing
  filenames and proves the test references the rule it claims to cover.
  """
  use ExUnit.Case, async: true

  @equivalence_glob "test/pattern/*_equivalence_test.exs"

  defp rules, do: Credence.RuleHelpers.discover_rules(Credence.Pattern.Rule)

  defp equivalence_sources do
    @equivalence_glob
    |> Path.wildcard()
    |> Map.new(fn path -> {path, File.read!(path)} end)
  end

  test "every Pattern rule has a behaviour-equivalence test module named for it" do
    sources = equivalence_sources()

    missing =
      for rule <- rules() do
        short = rule |> Module.split() |> List.last()
        needle = "defmodule Credence.Pattern.#{short}EquivalenceTest"
        {rule, Enum.any?(sources, fn {_path, body} -> String.contains?(body, needle) end)}
      end
      |> Enum.reject(fn {_rule, covered?} -> covered? end)
      |> Enum.map(fn {rule, _} -> rule end)

    assert missing == [],
           "rules with no behaviour-equivalence test " <>
             "(expected `Credence.Pattern.<Name>EquivalenceTest`):\n" <>
             Enum.map_join(missing, "\n", &("  - " <> inspect(&1)))
  end

  test "no behaviour-equivalence test is still an un-filled skeleton (:equivalence_todo)" do
    skeletons =
      equivalence_sources()
      |> Enum.filter(fn {_path, body} -> String.contains?(body, "equivalence_todo") end)
      |> Enum.map(fn {path, _body} -> path end)
      |> Enum.sort()

    assert skeletons == [],
           "skeleton equivalence tests still tagged :equivalence_todo " <>
             "(fill them — the backfill is meant to be complete):\n" <>
             Enum.map_join(skeletons, "\n", &("  - " <> &1))
  end
end
