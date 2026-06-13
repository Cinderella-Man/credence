defmodule Credence.Corpus.FindingsTest do
  @moduledoc """
  Unit tests for the finding→identity formatting that backs the corpus over-fire
  snapshot. Identities are `"<relpath>:<line>  <rule>"`, with an `(xN)` count
  collapsing exact duplicates. (The line comes straight from the issue, so there
  is no AST resolution to test.)
  """
  use ExUnit.Case, async: true

  alias Credence.Corpus.Findings

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
end
