defmodule Credence.Corpus.FixBreakageTest do
  @moduledoc """
  Asserts that NO accepted corpus fix is structurally broken — i.e. parses (so
  it clears `apply_rule_fix`'s parse-gate) yet would not compile, or silently
  changes behaviour. The parse-only gate and the comment/mangle/over-reach
  checks in `Credence.Corpus.FixSafetyTest` all miss this class.

  For every accepted `(file, rule)` in `accepted_findings.txt` we apply the
  rule's fix once and run `Credence.Corpus.FixBreakage`'s dependency-free
  detectors over the result. The test currently FAILS: there are known broken
  fixes in the shipped rules (a rule is reported as a finding but its fix is
  unsafe). The failure lists every one, grouped by rule. As each rule is
  narrowed so it stops emitting a broken fix, the list shrinks; when the last is
  fixed, the test goes green and becomes a permanent regression gate.
  """
  use ExUnit.Case, async: false

  @moduletag :corpus
  @moduletag timeout: 600_000

  alias Credence.Corpus
  alias Credence.Corpus.{FixBreakage, Progress}

  @progress_step 250

  setup_all do
    Corpus.ensure_fetched!()
    pairs = unique_pairs()

    IO.puts(
      "\n  [corpus] Fix-breakage: structurally checking #{length(pairs)} accepted (file, rule) fixes."
    )

    Progress.start(:breakage, length(pairs), @progress_step, "Fix-breakage checked", "fixes")
    on_exit(fn -> Progress.stop(:breakage) end)
    {:ok, pairs: pairs}
  end

  test "no accepted corpus fix is structurally broken", %{pairs: pairs} do
    broken =
      pairs
      |> Task.async_stream(
        fn {rel, rule} ->
          flags =
            try do
              FixBreakage.check(rule, rel)
            rescue
              _ -> []
            end

          Progress.tick(:breakage)
          {rel, rule, flags}
        end,
        max_concurrency: System.schedulers_online(),
        timeout: 120_000,
        ordered: false
      )
      |> Enum.flat_map(fn
        {:ok, {rel, rule, flags}} when flags != [] -> [{rule, rel, flags}]
        _ -> []
      end)
      |> Enum.sort()

    assert broken == [], report(broken)
  end

  # {rel, rule} for every accepted finding (one fix application per pair).
  defp unique_pairs do
    __DIR__
    |> Path.join("accepted_findings.txt")
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Stream.map(fn line ->
      [loc, rule | _] = String.split(line, ~r/\s+/)
      [path | _] = String.split(loc, ":")
      {path, rule}
    end)
    |> Enum.uniq()
  end

  defp report(broken) do
    by_rule =
      broken
      |> Enum.group_by(fn {rule, _, _} -> rule end)
      |> Enum.sort_by(fn {_, items} -> -length(items) end)

    body =
      Enum.map_join(by_rule, "\n\n", fn {rule, items} ->
        "  #{rule} (#{length(items)}):\n" <>
          Enum.map_join(items, "\n", fn {_, rel, flags} -> "    #{rel}  #{inspect(flags)}" end)
      end)

    """
    #{length(broken)} accepted corpus fixes are structurally broken — they parse but
    would not compile, or change behaviour. Each rule below reports a finding whose
    FIX is unsafe; narrow the rule so it stops emitting the bad fix.

    #{body}
    """
  end
end
