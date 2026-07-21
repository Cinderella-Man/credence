defmodule Credence.Corpus.AnalysisCache do
  @moduledoc """
  Run-wide, per-file cache of `Credence.Pattern.analyze/1` over the corpus.

  Several corpus layers need the same analysis of the same pinned files: the
  over-firing snapshot (via `Credence.Corpus.Findings`) and the fix-safety
  layer each swept the whole corpus independently before this cache existed
  (docs/13 P2). The corpus is immutable within a run (versions/SHAs pinned)
  and the rule set is fixed at compile time, so a file's path fully determines
  its findings — compute once, share everywhere.

  Concurrency: the table is `:public` and callers race benignly — the analysis
  is deterministic, so a duplicated computation inserts the same value.
  """

  @table __MODULE__

  @doc """
  Pattern findings for the file at `path`, computed once per run.

  Deliberately no claim/wait coordination: concurrent misses on the same path
  each compute and insert the same deterministic value. Blocking waiters on a
  claimant proved fragile under load (a killed claimant strands its claim and
  stalls every waiter — observed as cascading `Task.async_stream` timeouts);
  duplicated computation is benign and bounded, and the sweeps that share this
  cache walk the corpus from opposite ends to keep the overlap window small.
  """
  @spec analyze(String.t()) :: [Credence.Issue.t()]
  def analyze(path) do
    ensure_table!()

    case :ets.lookup(@table, path) do
      [{^path, issues}] ->
        issues

      [] ->
        issues = Credence.Pattern.analyze(File.read!(path))
        :ets.insert(@table, {path, issues})
        issues
    end
  end

  # The named table must outlive whichever short-lived caller touches the cache
  # first (an ExUnit test process would take the table down with it at test
  # exit), so a dedicated eternal process is spawned to own it. Losing the
  # creation race to a concurrent caller is fine — the table exists either way.
  defp ensure_table! do
    if :ets.whereis(@table) == :undefined, do: create_table()
    :ok
  end

  defp create_table do
    caller = self()

    spawn(fn ->
      try do
        :ets.new(@table, [
          :named_table,
          :public,
          :set,
          read_concurrency: true,
          write_concurrency: true
        ])

        send(caller, {__MODULE__, :ready})
        Process.sleep(:infinity)
      rescue
        ArgumentError -> send(caller, {__MODULE__, :ready})
      end
    end)

    receive do
      {__MODULE__, :ready} -> :ok
    end
  end
end
