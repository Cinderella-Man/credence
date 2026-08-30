defmodule Credence.CredenceInternalsDocTest do
  use ExUnit.Case, async: true

  @doc_path Path.expand("../docs/research/credence-internals.md", __DIR__)

  test "the research report describes the current compile containment and Semantic guard" do
    report = File.read!(@doc_path)

    expected =
      "The **Pattern** round compiles and reverts each changed rule. The **Semantic** round re-measures\n" <>
        "every changed pass, attributes parse/compile regressions or strictly-added unrepaired errors,\n" <>
        "reverts culpable fixes, and records them as `:reverted`; ambiguous unsafe replay reverts the whole\n" <>
        "pass. The **Syntax** round still applies each text fix and only logs whether the result parses at\n" <>
        "the end, without reverting. Thus Pattern and Semantic now have different repair-safety gates,\n" <>
        "while Syntax remains the unguarded phase."

    assert Regex.scan(Regex.compile!(Regex.escape(expected)), report) == [[expected]]
  end

  test "the scale snapshot agrees exactly with the live rule files" do
    report = File.read!(@doc_path)

    for {phase, label} <- [pattern: "Pattern", semantic: "Semantic", syntax: "Syntax"] do
      count =
        Path.wildcard(Path.expand("../lib/#{phase}/*.ex", __DIR__))
        |> Enum.reject(&(Path.basename(&1) == "rule.ex"))
        |> length()

      expected = "**#{count} #{label} rules**"
      assert Regex.scan(Regex.compile!(Regex.escape(expected)), report) == [[expected]]
    end
  end

  test "the priority discussion points to the policy and current override inventory" do
    report = File.read!(@doc_path)

    expected =
      "The priority mechanism is documented in `docs/20-rule-ordering-policy.md`: a non-default priority\n" <>
        "must state the ordering assertion it makes, contended Semantic diagnostics must be decided by a\n" <>
        "declared priority, and independent rules should remain at 500. Currently 18 rules declare an\n" <>
        "override (7 Pattern, 11 Semantic, no Syntax); 153/160 Pattern and all 46 discovered Syntax rules\n" <>
        "therefore still use the alphabetical tiebreak. That is expected for independent rules but remains\n" <>
        "a hazard if an interaction is not identified and declared under the policy."

    assert Regex.scan(Regex.compile!(Regex.escape(expected)), report) == [[expected]]
  end
end
