defmodule Credence.Corpus.OverFiringTest do
  @moduledoc """
  Over-firing *regression* layer: runs Credence's Pattern checks over the `lib/`
  source of ~10 popular hex packages (see `Credence.Corpus`) and asserts the set
  of findings has not drifted from a reviewed, committed snapshot
  (`test/corpus/accepted_findings.txt`).

  Each finding is resolved to a stable identity — `<path>:<line>  <rule>` (see
  `Credence.Corpus.Findings`) — and pinned. Comparing the live set to the pin
  per package means:

    * a NEW finding (Credence flagging code it didn't before) fails the test as a
      candidate over-fire — it is not silently swallowed by a rule-level
      allowlist, so you find out the moment a rule starts over-firing; and
    * a GONE finding (a rule narrowed or was removed) also fails, prompting an
      intentional re-pin.

  Scope is the Pattern phase via `Credence.Pattern.analyze/2` — parse-only, no
  compilation, so it is fast (~5s for the whole corpus) and `async`-safe. On
  clean code the Syntax phase never fires (the source parses) and the Semantic
  phase never fires (no rule-matching warnings), so `Pattern.analyze` is the same
  over-fire signal the full pipeline would give, at a fraction of the cost.

  Runs in the default `mix test` suite. When the drift is expected, accept it:

      mix credence.corpus --update-snapshot

  Still tagged `:corpus`, so it can be skipped for a quicker run:

      mix test --exclude corpus
  """
  use ExUnit.Case, async: true

  @moduletag :corpus

  alias Credence.Corpus.Findings

  setup_all do
    Credence.Corpus.ensure_fetched!()
    :ok
  end

  for {pkg, version} <- Credence.Corpus.packages() do
    test "corpus findings on #{pkg} v#{version} match the accepted snapshot" do
      pkg = unquote(pkg)
      version = unquote(version)

      files = Credence.Corpus.lib_files(pkg)
      assert files != [], "no lib/*.ex found for #{pkg} — corpus fetch may have failed"

      actual = Findings.for_package(pkg)

      expected =
        Findings.snapshot_lines()
        |> Enum.filter(&String.starts_with?(&1, "#{pkg}/"))
        |> Enum.sort()

      assert actual == expected, drift_message(pkg, version, actual, expected)
    end
  end

  defp drift_message(pkg, version, actual, expected) do
    added = actual -- expected
    removed = expected -- actual

    """
    Corpus findings for #{pkg} v#{version} drifted from the accepted snapshot
    (test/corpus/accepted_findings.txt).

    NEW — not previously accepted (a candidate OVER-FIRE — investigate!):
    #{bullets(added)}

    GONE — pinned but no longer firing (a rule narrowed / was removed — fine to re-pin):
    #{bullets(removed)}

    If these changes are expected, re-pin with:
        mix credence.corpus --update-snapshot
    """
  end

  defp bullets([]), do: "  (none)"
  defp bullets(lines), do: "  " <> Enum.join(lines, "\n  ")
end
