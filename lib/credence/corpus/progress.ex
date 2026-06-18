defmodule Credence.Corpus.Progress do
  @moduledoc """
  Lightweight, parallel-safe progress counters for the corpus test layers.

  Both corpus suites run one `async` test per entry, so work happens concurrently
  across schedulers. `start/5` registers a shared, lock-free `:atomics` counter
  (in `:persistent_term`) under a caller-chosen `key`; `tick/1` bumps it and
  prints a `<verb> Q out of P <unit>` line every `step` ticks (and on the last).

  Each phase uses its own `key` (the over-firing analyze pass and the fix-safety
  pass run in the same `mix test` and would otherwise clobber one counter), so
  they report independently. `tick/1` is a no-op when no tracker is registered
  for the key, keeping the same code paths silent under the `mix credence.corpus`
  task and the rule unit tests.
  """

  @doc "Register a counter `key` for `total` items, reporting every `step` as `\"<verb> Q out of P <unit>\"`."
  @spec start(atom(), non_neg_integer(), pos_integer(), String.t(), String.t()) :: :ok
  def start(key, total, step, verb, unit)
      when is_atom(key) and is_integer(total) and is_integer(step) and step > 0 do
    ref = :atomics.new(1, signed: false)
    :persistent_term.put(pt_key(key), {ref, total, step, verb, unit})
    :ok
  end

  @doc "Count one item for `key`; print progress at each `step` boundary."
  @spec tick(atom()) :: :ok
  def tick(key) do
    case :persistent_term.get(pt_key(key), nil) do
      nil ->
        :ok

      {ref, total, step, verb, unit} ->
        n = :atomics.add_get(ref, 1, 1)

        if rem(n, step) == 0 or n == total do
          IO.puts("  [corpus] #{verb} #{n} out of #{total} #{unit}")
        end

        :ok
    end
  end

  @doc "Remove the tracker for `key` (subsequent `tick/1` calls are no-ops)."
  @spec stop(atom()) :: :ok
  def stop(key) do
    :persistent_term.erase(pt_key(key))
    :ok
  end

  defp pt_key(key), do: {__MODULE__, key}
end
