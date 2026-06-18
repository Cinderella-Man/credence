defmodule Credence.Corpus.Progress do
  @moduledoc """
  Lightweight, parallel-safe progress counter for the corpus over-firing test.

  The over-firing suite runs one `async` test per corpus entry, so files are
  validated concurrently across schedulers. `start/2` registers a shared,
  lock-free `:atomics` counter (in `:persistent_term`); `tick/0` — called once
  per validated file from `Credence.Corpus.Findings` — bumps it and prints a
  `Validated Q out of P files` line every `step` files (and on the last one).

  `tick/0` is a no-op when no tracker is registered, so the same `Findings` code
  path used by the `mix credence.corpus` task and the rule unit tests stays
  silent — only the over-firing test opts in.
  """

  @key {__MODULE__, :tracker}

  @doc "Register a counter for `total` files, reporting every `step` files."
  @spec start(non_neg_integer(), pos_integer()) :: :ok
  def start(total, step) when is_integer(total) and is_integer(step) and step > 0 do
    ref = :atomics.new(1, signed: false)
    :persistent_term.put(@key, {ref, total, step})
    :ok
  end

  @doc "Count one validated file; print progress at each `step` boundary."
  @spec tick() :: :ok
  def tick do
    case :persistent_term.get(@key, nil) do
      nil ->
        :ok

      {ref, total, step} ->
        n = :atomics.add_get(ref, 1, 1)

        if rem(n, step) == 0 or n == total do
          IO.puts("  [corpus] Validated #{n} out of #{total} files")
        end

        :ok
    end
  end

  @doc "Remove the tracker (subsequent `tick/0` calls are no-ops)."
  @spec stop() :: :ok
  def stop do
    :persistent_term.erase(@key)
    :ok
  end
end
