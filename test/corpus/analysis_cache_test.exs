defmodule Credence.Corpus.AnalysisCacheTest do
  @moduledoc """
  The corpus analysis cache is shared by every corpus layer, and since docs/13
  P3 the same file is analyzed both with the full rule set and with a single
  rule (`mix credence.corpus --only-rule`). A scoped result is a strict subset
  of the full one, so if the two shared a cache entry a scoped sweep would hand
  the next full-scan caller a silently truncated answer: no crash, no drift
  message, just an over-firing layer that stops seeing 154 rules.

  These tests pin that the analysis scope is part of the key, and that the cache
  is a cache — a hit is observed directly, by deleting the file between calls.
  """
  use ExUnit.Case, async: true

  alias Credence.Corpus.AnalysisCache

  @one_rule Credence.Pattern.NoUniqThenCount

  # Trips three rules at once, so the scoped answer is a visibly strict subset.
  @source """
  defmodule Probe do
    def a(list), do: list |> Enum.uniq() |> Enum.count()
    def b(n), do: n * 1.0
  end
  """

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "credence_analysis_cache_#{System.unique_integer([:positive])}.ex"
      )

    File.write!(path, @source)
    on_exit(fn -> File.rm(path) end)
    {:ok, path: path}
  end

  test "the fixture trips more than one rule (otherwise nothing below is a test)", %{path: path} do
    assert length(AnalysisCache.analyze(path)) > 1
  end

  test "a scoped analysis does not poison the later full-scan answer", %{path: path} do
    scoped = AnalysisCache.analyze(path, rules: [@one_rule])
    full = AnalysisCache.analyze(path)

    assert Enum.map(scoped, & &1.rule) == [:no_uniq_then_count]
    assert :prefer_erlang_float in Enum.map(full, & &1.rule)
    assert length(full) > length(scoped)
  end

  test "a full analysis does not poison a later scoped answer", %{path: path} do
    full = AnalysisCache.analyze(path)
    scoped = AnalysisCache.analyze(path, rules: [@one_rule])

    assert length(full) > 1
    assert Enum.map(scoped, & &1.rule) == [:no_uniq_then_count]
  end

  test "the second read of the same scope is a cache hit, not a re-read", %{path: path} do
    first = AnalysisCache.analyze(path)
    File.rm!(path)

    # A miss here would `File.read!` a file that no longer exists and raise.
    assert AnalysisCache.analyze(path) == first
  end

  test "naming the same rules in a different order hits the same entry", %{path: path} do
    rules = [@one_rule, Credence.Pattern.PreferErlangFloat]
    first = AnalysisCache.analyze(path, rules: rules)
    File.rm!(path)

    assert AnalysisCache.analyze(path, rules: Enum.reverse(rules)) == first
    assert length(first) == 2
  end
end
