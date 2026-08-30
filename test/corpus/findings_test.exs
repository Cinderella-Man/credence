defmodule Credence.Corpus.FindingsTest do
  @moduledoc """
  Unit tests for the finding→identity formatting that backs the corpus over-fire
  snapshot. Identities are `"<relpath>:<line>  <rule>"`, with an `(xN)` count
  collapsing exact duplicates. (The line comes straight from the issue, so there
  is no AST resolution to test.)

  Also covers reading an identity back: `rule_of/1` and `only_rule/2` slice the
  snapshot down to one rule, which is the accepted-findings half of the
  `mix credence.corpus --only-rule` gate (docs/13 P3).
  """
  use ExUnit.Case, async: true

  alias Credence.Corpus.Findings

  # The trap `only_rule/2` has to avoid: a corpus path can contain a rule's name
  # (credence's own corpus ships credo, styler and recode, whose files are named
  # after checks). A substring match would count another rule's finding as
  # accepted for this one — inflating the accepted set and hiding an over-fire.
  @lines [
    "jason/lib/jason.ex:10  no_uniq_then_count",
    "jason/lib/jason.ex:11  no_uniq_then_count  (x3)",
    "credo/lib/credo/check/no_uniq_then_count.ex:7  prefer_erlang_float",
    "elixir_lang/lib/enum.ex:99  no_sort_then_at"
  ]

  test "formats a finding as path:line  rule" do
    assert Findings.format([{"a/b.ex", 10, :some_rule}]) == ["a/b.ex:10  some_rule"]
  end

  test "collapses exact duplicates with an (xN) count" do
    assert Findings.format([{"a.ex", 10, :r}, {"a.ex", 10, :r}, {"a.ex", 10, :r}]) ==
             ["a.ex:10  r  (x3)"]
  end

  test "keeps findings on distinct lines or with distinct rules separate" do
    assert Findings.format([{"a.ex", 10, :r}, {"a.ex", 11, :r}, {"a.ex", 10, :s}]) ==
             ["a.ex:10  r", "a.ex:10  s", "a.ex:11  r"]
  end

  test "a finding with no line gets a stable :? placeholder" do
    assert Findings.format([{"a.ex", nil, :r}]) == ["a.ex:?  r"]
  end

  test "output is lexicographically sorted and deterministic" do
    assert Findings.format([{"z.ex", 1, :r}, {"a.ex", 2, :r}, {"a.ex", 10, :r}]) ==
             ["a.ex:10  r", "a.ex:2  r", "z.ex:1  r"]
  end

  describe "rule_of/1" do
    test "reads the rule back off a formatted identity" do
      assert Findings.rule_of("jason/lib/jason.ex:10  no_uniq_then_count") ==
               "no_uniq_then_count"
    end

    test "reads the rule back off a duplicate-collapsed identity" do
      assert Findings.rule_of("jason/lib/jason.ex:10  no_uniq_then_count  (x3)") ==
               "no_uniq_then_count"
    end

    test "round-trips whatever format/1 produced" do
      for line <- Findings.format([{"a.ex", 1, :r_one}, {"a.ex", 2, :r_two}, {"a.ex", 2, :r_two}]) do
        assert Findings.rule_of(line) in ["r_one", "r_two"]
      end
    end

    test "is nil for a line that is not an identity" do
      assert Findings.rule_of("# a comment") == nil
      assert Findings.rule_of("") == nil
    end
  end

  describe "only_rule/2" do
    test "keeps only the lines whose RULE field matches" do
      assert Findings.only_rule(@lines, "no_uniq_then_count") == Enum.take(@lines, 2)
    end

    test "does not match a rule name appearing in the path" do
      refute Enum.any?(
               Findings.only_rule(@lines, "no_uniq_then_count"),
               &String.contains?(&1, "prefer_erlang_float")
             )
    end

    test "is empty for a rule with no accepted findings — the new-rule case" do
      assert Findings.only_rule(@lines, "a_brand_new_rule") == []
    end

    test "partitions the input: every line belongs to exactly one rule" do
      by_rule = Enum.map(@lines, &Findings.rule_of/1) |> Enum.uniq()
      recombined = Enum.flat_map(by_rule, &Findings.only_rule(@lines, &1))
      assert Enum.sort(recombined) == Enum.sort(@lines)
    end
  end
end
