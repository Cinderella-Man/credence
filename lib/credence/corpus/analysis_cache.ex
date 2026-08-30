defmodule Credence.Corpus.AnalysisCache do
  @moduledoc """
  Run-wide, per-file cache of `Credence.Pattern.analyze/2` over the corpus.

  Several corpus layers need the same analysis of the same pinned files: the
  over-firing snapshot (via `Credence.Corpus.Findings`) and the fix-safety
  layer each swept the whole corpus independently before this cache existed
  (docs/13 P2). The corpus is immutable within a run (versions/SHAs pinned)
  and the rule set is fixed at compile time, so a file's path fully determines
  its findings — compute once, share everywhere.

  ## The analysis *scope* is part of the key

  Since docs/13 P3 the same file is also analyzed with a **single** rule
  (`mix credence.corpus --only-rule`, `Findings.all(rules: [R])`). Those
  findings are a strict subset of the full-rule-set findings, so filing them
  under the bare path would let a scoped sweep hand a later full-sweep caller a
  silently truncated answer — the worst kind of wrong: no crash, no drift
  message, just a corpus layer that stops seeing 154 rules. The key is
  therefore `{path, normalized_opts}`: a scoped result can never be mistaken
  for a full one, and the two coexist in the same table.

  Concurrency: the table is `:public` and callers race benignly — the analysis
  is deterministic, so a duplicated computation inserts the same value.
  """

  @table __MODULE__

  @doc """
  Pattern findings for the file at `path`, computed once per run per `opts`.

  `opts` is passed straight through to `Credence.Pattern.analyze/2` — notably
  `rules: [R]` for a rule-scoped sweep — and participates in the cache key.

  Deliberately no claim/wait coordination: concurrent misses on the same key
  each compute and insert the same deterministic value. Blocking waiters on a
  claimant proved fragile under load (a killed claimant strands its claim and
  stalls every waiter — observed as cascading `Task.async_stream` timeouts);
  duplicated computation is benign and bounded, and the sweeps that share this
  cache walk the corpus from opposite ends to keep the overlap window small.
  """
  @spec analyze(String.t(), keyword()) :: [Credence.Issue.t()]
  def analyze(path, opts \\ []) do
    ensure_table!()
    key = cache_key(path, opts)

    case :ets.lookup(@table, key) do
      [{^key, issues}] ->
        issues

      [] ->
        issues = Credence.Pattern.analyze(File.read!(path), opts)
        :ets.insert(@table, {key, issues})
        issues
    end
  end

  # Two callers naming the same rules in a different order are asking the same
  # question, so the rule list is sorted before it becomes part of the key (the
  # engine's own ordering is by priority, not by the caller's list order).
  # Everything else in `opts` is taken as given: an option this module does not
  # understand can still change the answer, so it must change the key.
  defp cache_key(path, opts) do
    normalized =
      case Keyword.fetch(opts, :rules) do
        {:ok, rules} -> Keyword.put(opts, :rules, Enum.sort(rules))
        :error -> opts
      end

    {path, Enum.sort(normalized)}
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
