defmodule Credence.MutantsTaskTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Credence.Mutants

  test "rejects unknown command-line options" do
    assert_raise Mix.Error, ~r/--rul/, fn ->
      Mutants.parse_options!(["--rul", "no_manual_max"])
    end
  end

  test "a stratified sample contains exactly the requested number of rules" do
    subjects =
      for {layer, count} <- [pattern: 161, syntax: 47, semantic: 93], index <- 1..count do
        %{layer: layer, module: Module.concat([layer, "Rule#{index}"])}
      end

    sample = Mutants.sample(subjects, sample: 8, seed: 0)

    assert length(sample) == 8
    assert Enum.frequencies_by(sample, & &1.layer) == %{pattern: 4, syntax: 1, semantic: 3}
  end

  test "survivor source context escapes Markdown table separators" do
    mutant = %{
      line: 12,
      column: 4,
      operator: :boolean_flip,
      original: "true",
      replacement: "false",
      context: "value |> transform()"
    }

    report = %{
      subject: %{name: "example_rule", source_path: "lib/example_rule.ex"},
      results: [%{status: :survived, mutant: mutant}]
    }

    assert Mutants.survivor_table([report]) == """
           Each row is a behaviour change the rule's own tests did not notice —
           **or** an equivalent mutant (docs/14 E6). Triage before acting.

           | rule | site | operator | mutation | source line |
           | --- | --- | --- | --- | --- |
           | example_rule | lib/example_rule.ex:12:4 | boolean_flip | `true` → `false` | `value \\|> transform()` |
           """
  end
end
