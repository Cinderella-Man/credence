defmodule Mix.Tasks.Credence.Corpus do
  @shortdoc "Run Credence's Pattern phase over the real-world corpus and report findings"

  @moduledoc """
  Runs `Credence.Pattern.analyze/2` over the `lib/` source of the pinned popular
  hex packages in `corpus/` (see `Credence.Corpus`) and reports what Credence
  flags — the over-firing signal.

      mix credence.corpus                     # summary: totals, crashes, counts by rule + package
      mix credence.corpus <rule>              # every occurrence of <rule> with file:line + source
      mix credence.corpus --only-rule <rule>  # over-fire GATE for one rule (drift vs the snapshot)
      mix credence.corpus --update-snapshot   # re-pin the accepted-findings snapshot
      mix credence.corpus --budget            # per-rule accepted-findings budget (no corpus needed)
      mix credence.corpus --update-budget     # re-publish the budget from the committed snapshot

  Fetch the corpus first with `mix credence.corpus.fetch` (or run `mix test`,
  which auto-fetches). A *crash* (a rule raising on valid code) is worse than a
  finding and is reported separately.

  The two budget modes are the exception: they read the *committed snapshot*,
  not the corpus, so they need no fetch and run instantly.

  The summary/`<rule>` modes report the *raw* Pattern findings. The over-firing
  test (`test/corpus/over_firing_test.exs`) instead compares the findings,
  resolved to `<path>:<line>  <rule>` identities, against the committed snapshot
  `test/corpus/accepted_findings.txt`. `--update-snapshot` regenerates that
  snapshot from the current corpus — run it after reviewing the drift the test
  reports, to accept the new set.

  ## `--budget` / `--update-budget` — the per-rule budget (docs/12 C13)

  The over-firing test ratchets *code* changes: no rule can start firing without
  going red. It does not ratchet the *accept* — its failure message points at
  `--update-snapshot`, the re-pin is one command, and what lands in review is N
  raw `<path>:<line>  <rule>` lines with no per-rule aggregate anywhere. That is
  how the snapshot reached 6,366 accepted findings across 87 rules, 74% of them
  in 15 rules, without anyone deciding to.

  `test/corpus/accepted_findings_budget.txt` is the per-rule view of the same
  snapshot, counted with `(xN)` multiplicity, and
  `test/corpus/findings_budget_test.exs` gates it: the file must match the
  snapshot exactly, a rule off the frozen grandfather ledger may not exceed 100
  accepted findings, a grandfathered rule may not exceed its adoption-day
  ceiling, and it must leave the ledger once it falls to the cap.

    * `--budget` prints the ranked table with the over-cap rules marked. That
      ranking is also the paydown order, and it is derived from the committed
      snapshot, so it costs nothing to run.
    * `--update-budget` re-publishes the file after a re-pin. `--update-snapshot`
      deliberately does **not** write it: the harness's
      `Cev.Evolve.Corpus.delta/1` uses `--update-snapshot` as a read-only probe
      (regenerate → read → restore the snapshot file), and a second file written
      behind its back would be left dirty in the clone and would redden the gate
      spuriously on the next row. So `--update-snapshot` only *reports* the
      per-rule delta its re-pin costs, and names the command that publishes it.

  ## `--only-rule` — the rule-scoped scan (docs/13 P3)

  `--only-rule` answers the one question a Gate asks about a candidate that
  touches exactly one Pattern rule: *does this rule over-fire on the corpus?*
  It sweeps the corpus with `rules: [R]` and diffs the resulting identity lines
  against the snapshot's lines **for that rule only**, so it is the over-firing
  test restricted to one rule — same sweep code (`Credence.Corpus.Findings`),
  same identities, same snapshot.

  That restriction is sound because findings are per-rule independent:
  `Pattern.analyze/2` `flat_map`s each rule's `check` over the same parsed AST
  with no cross-rule state (`lib/pattern.ex`), confirmed empirically in docs/14
  E3 and re-verified on this corpus (0 mismatches over 2,008 files x 155 rules).

  Measured on the 20,076-file corpus, 24 schedulers: the scoped analysis sweep
  is **8.2 s** against **56.6 s** for the full rule set, and ~12 s against ~57 s
  end to end through this task. The win is ~6.5x, not ~155x, because a one-rule
  sweep is parse-bound — ~95% of it is `Sourceror.parse_string/1`, which the
  P4 AST cache, not this change, is what removes.

  Exit status is the interface: **0** when the rule's live findings equal its
  accepted findings, **1** on drift or on any operational failure (unknown rule,
  corpus missing). A `RESULT=` line distinguishes them:

      [only-rule] RESULT=clean rule=no_uniq_then_count live=19 accepted=19
      [only-rule] RESULT=drift rule=no_uniq_then_count live=21 accepted=19 new=2 gone=0

  Only Pattern rules can be scoped, and that is not a limitation: every corpus
  layer (over-firing, fix-safety, scope-parity, fix-breakage) is Pattern-only,
  so a candidate touching only `lib/syntax/` or `lib/semantic/` needs no corpus
  scan at all. Naming a Syntax/Semantic rule here says exactly that and exits 1.
  """

  use Mix.Task

  alias Credence.Corpus
  alias Credence.Corpus.{Budget, Findings, Progress}

  # Emit a progress line every this-many scanned files during a scoped sweep.
  @progress_step 5000

  # Lines of source shown for each drifted finding.
  @context 1

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("compile")

    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          update_snapshot: :boolean,
          only_rule: :string,
          budget: :boolean,
          update_budget: :boolean
        ]
      )

    modes = Enum.filter([:update_snapshot, :only_rule, :budget, :update_budget], &opts[&1])

    cond do
      invalid != [] ->
        Mix.raise("unknown option #{inspect(Enum.map(invalid, &elem(&1, 0)))}.\n#{usage()}")

      length(modes) > 1 ->
        Mix.raise("#{inspect(modes)} are separate modes; pass one.\n#{usage()}")

      opts[:budget] && rest != [] ->
        Mix.raise("--budget takes no other arguments.\n#{usage()}")

      # Derived from the COMMITTED snapshot, so no corpus fetch and no analysis.
      opts[:budget] ->
        report_budget()

      opts[:update_budget] && rest != [] ->
        Mix.raise("--update-budget takes no other arguments.\n#{usage()}")

      opts[:update_budget] ->
        update_budget()

      opts[:update_snapshot] && rest != [] ->
        Mix.raise("--update-snapshot takes no other arguments.\n#{usage()}")

      opts[:update_snapshot] ->
        Corpus.ensure_fetched!()
        update_snapshot()

      opts[:only_rule] && rest != [] ->
        Mix.raise("--only-rule takes no other arguments.\n#{usage()}")

      opts[:only_rule] ->
        assert_complete_corpus!(Corpus.entries(), &Corpus.fetched?/1)
        report_only_rule(opts[:only_rule])

      rest == [] ->
        require_corpus!()
        {findings, crashes} = analyze_corpus()
        report_summary(findings, crashes)

      match?([_], rest) ->
        require_corpus!()
        [rule] = rest
        # Scoped scan (docs/13 P3): findings are per-rule independent, so
        # sweeping with just this rule yields exactly the lines the full scan
        # would attribute to it. `report_rule/2` still filters and still sorts,
        # so the output is identical to the serial full-scan-then-filter this
        # replaces — which measured 55.5 s on a 1,172-file slice, i.e. ~16
        # minutes over the whole corpus.
        derived = resolve_rule!(rule)
        {findings, _crashes} = analyze_corpus(rules: [derived.rule_module])
        report_rule(findings, derived.atom)

      true ->
        Mix.raise(usage())
    end
  end

  defp usage do
    "usage: mix credence.corpus " <>
      "[<rule> | --only-rule <rule> | --update-snapshot | --budget | --update-budget]"
  end

  defp require_corpus! do
    if Enum.all?(Corpus.entries(), fn {name, _} -> not Corpus.fetched?(name) end) do
      Mix.raise(
        "No corpus found in #{Corpus.root()}/. " <>
          "Run `mix credence.corpus.fetch` first (or `mix test`)."
      )
    end
  end

  @doc false
  def assert_complete_corpus!(entries, fetched?) do
    missing = for {name, _} <- entries, not fetched?.(name), do: name

    cond do
      length(missing) == length(entries) ->
        Mix.raise(
          "No corpus found in #{Corpus.root()}/. " <>
            "Run `mix credence.corpus.fetch` first (or `mix test`)."
        )

      missing != [] ->
        Mix.raise(
          "The corpus is incomplete; missing #{length(missing)} of #{length(entries)} entries " <>
            "(including #{missing |> Enum.take(5) |> Enum.map_join(", ", &to_string/1)}). " <>
            "Run `mix credence.corpus.fetch` before using --only-rule."
        )

      true ->
        :ok
    end
  end

  @doc """
  Resolve a user-supplied rule name to its `Credence.RuleName` derivation,
  raising with a usable message when it is not a live Pattern rule.

  Accepts the snake name (`no_uniq_then_count`), the short Pascal name
  (`NoUniqThenCount`) or the full module (`Credence.Pattern.NoUniqThenCount`,
  with or without the `Elixir.` prefix). A name that is not in
  `Credence.Pattern.default_rules/0` raises rather than reporting zero
  occurrences: a typo that silently answers "this rule is clean" is precisely
  the failure this task exists to catch.
  """
  @spec resolve_rule!(String.t()) :: Credence.RuleName.derived()
  def resolve_rule!(name) do
    short =
      name
      |> String.trim()
      |> String.replace_prefix("Elixir.", "")
      |> String.replace_prefix("Credence.Pattern.", "")

    cond do
      String.starts_with?(short, ["Credence.Syntax.", "Credence.Semantic."]) ->
        Mix.raise(
          "#{name} is not a Pattern rule, and the corpus layer is Pattern-only " <>
            "(over-firing, fix-safety, scope-parity and fix-breakage all analyze via " <>
            "Credence.Pattern). A candidate that touches only lib/syntax/ or lib/semantic/ " <>
            "cannot change any corpus verdict — skip the corpus phase entirely (docs/13 P3)."
        )

      String.contains?(short, ".") ->
        Mix.raise("#{name} is not a Credence rule module.\n#{known_rules_hint()}")

      true ->
        derived = Credence.RuleName.derive(short, :pattern)

        if derived.rule_module in Credence.Pattern.default_rules() do
          derived
        else
          Mix.raise("unknown Pattern rule #{inspect(name)}.\n#{known_rules_hint()}")
        end
    end
  end

  defp known_rules_hint do
    rules = Credence.Pattern.default_rules()

    example =
      rules
      |> Enum.map(&Credence.RuleHelpers.rule_name/1)
      |> Enum.sort()
      |> List.first()

    "Expected one of the #{length(rules)} rules in Credence.Pattern.default_rules/0, " <>
      "named as a snake name, a short Pascal name or a full module — e.g. #{example}."
  end

  # The rule-scoped over-fire gate. Same sweep and same identities as
  # `test/corpus/over_firing_test.exs`, restricted to one rule on both sides:
  # the live findings come from `rules: [module]`, the accepted findings from
  # the snapshot lines whose rule field is this rule.
  defp report_only_rule(name) do
    shell = Mix.shell()
    %{rule_module: module, snake: snake} = resolve_rule!(name)
    assert_enabled!(module, snake, Credence.Pattern.rule_status([]))

    total = Enum.sum(for {entry, _} <- Corpus.entries(), do: length(Corpus.lib_files(entry)))
    Progress.start(:analyze, total, @progress_step, "Scanned", "files")

    {micros, actual} = :timer.tc(fn -> Findings.all(rules: [module]) end)
    Progress.stop(:analyze)

    expected = Findings.snapshot_lines() |> Findings.only_rule(snake)
    {new, gone} = drift(actual, expected)

    shell.info(
      "\n[only-rule] #{snake} — scanned #{total} file(s) across #{length(Corpus.entries())} " <>
        "corpus entries in #{Float.round(micros / 1_000_000, 1)}s"
    )

    if new == [] and gone == [] do
      shell.info(
        "[only-rule] RESULT=clean rule=#{snake} live=#{length(actual)} " <>
          "accepted=#{length(expected)}"
      )
    else
      shell.info("\nNEW — not previously accepted (a candidate OVER-FIRE — investigate!):")
      shell.info(explain(new))
      shell.info("\nGONE — pinned but no longer firing (a rule narrowed / was removed):")
      shell.info(bullets(gone))

      shell.info(
        "\n[only-rule] RESULT=drift rule=#{snake} live=#{length(actual)} " <>
          "accepted=#{length(expected)} new=#{length(new)} gone=#{length(gone)}"
      )

      Mix.raise(
        "corpus drift for #{snake}: #{length(new)} new, #{length(gone)} gone. " <>
          "If this is expected, review it and re-pin with `mix credence.corpus --update-snapshot`."
      )
    end
  end

  @doc """
  Refuse to scope the scan to a rule the assumption filter would switch off.

  `Credence.Pattern.analyze/2` filters an explicit `rules:` list by assumptions
  just like the default set, so a rule whose promises are off produces no
  findings — and a corpus scan would then print `RESULT=clean` for a rule it
  never ran. The full scan excludes it too, so this is not a *wrong* answer; it
  is a **vacuous** one, and a Gate cannot tell the two apart. Raise instead.

  Takes the status list rather than computing it, so the decision is testable
  without a rule that happens to be gated today (none is).
  """
  @spec assert_enabled!(module(), String.t(), [map()]) :: :ok
  def assert_enabled!(module, snake, statuses) do
    case Enum.find(statuses, &(&1.rule == module)) do
      %{enabled: false, missing: missing} ->
        Mix.raise(
          "#{snake} is switched off under the default assumptions (missing " <>
            "#{inspect(missing)}), so a scoped corpus scan would report it clean without " <>
            "ever running it. Turn the assumption on (config :credence, :assumptions) " <>
            "before scanning, or scan the full corpus."
        )

      _ ->
        :ok
    end
  end

  @doc """
  The `{new, gone}` split between a rule's live identity lines and its accepted
  ones — `new` is the over-fire signal, `gone` the narrowing signal.

  Both directions fail the gate, exactly as in the over-firing test: a finding
  that disappeared is a rule that quietly stopped covering pinned code, which is
  as much a regression as one that appeared.
  """
  @spec drift([String.t()], [String.t()]) :: {[String.t()], [String.t()]}
  def drift(actual, accepted), do: {actual -- accepted, accepted -- actual}

  defp bullets([]), do: "  (none)"
  defp bullets(lines), do: "  " <> Enum.join(lines, "\n  ")

  defp explain([]), do: "  (none)"

  # Each NEW line gets its offending source inline, so the drift can be judged
  # without opening the file. Best-effort: an unreadable file degrades to the
  # bare line rather than losing the report.
  defp explain(lines) do
    Enum.map_join(lines, "\n", fn line ->
      with [_, rel, lineno] <- Regex.run(~r/^(\S+):(\d+)\s/, line),
           {:ok, source} <- File.read(Path.join(Corpus.root(), rel)) do
        "  • #{line}\n#{excerpt(source, String.to_integer(lineno))}"
      else
        _ -> "  • #{line}"
      end
    end)
  end

  defp excerpt(source, lineno) do
    lines = String.split(source, "\n")
    lo = max(lineno - @context, 1)
    hi = min(lineno + @context, length(lines))

    Enum.map_join(lo..hi, "\n", fn n ->
      marker = if n == lineno, do: ">", else: " "
      "      #{marker} #{n} | #{Enum.at(lines, n - 1)}"
    end)
  end

  defp update_snapshot do
    published = Budget.published()
    lines = Findings.all()
    path = Findings.snapshot_path()
    File.write!(path, snapshot_header() <> Enum.join(lines, "\n") <> "\n")

    Mix.shell().info(
      "Wrote #{length(lines)} accepted finding(s) to #{Path.relative_to_cwd(path)}."
    )

    report_budget_delta(published, Budget.counts(lines), :stale)
  end

  # What moved, per rule. The snapshot diff alone cannot say — it is N raw path
  # lines — and the per-rule number nobody was ever shown is exactly how the
  # whitelist reached 6,366 (docs/12 C13).
  #
  # `mode` is what the caller should do about it: `:stale` (the budget file has
  # NOT been rewritten, so the gate is now red) or `:published` (it just was).
  # `--update-snapshot` is deliberately `:stale`: writing the budget file there
  # would break the harness's read-only `--update-snapshot` probe.
  defp report_budget_delta(published, counts, mode) do
    shell = Mix.shell()
    deltas = Budget.deltas(published, counts)

    cond do
      published == %{} and mode == :stale ->
        shell.info(
          "\n[budget] no per-rule budget published yet — create it with " <>
            "`mix credence.corpus --update-budget`."
        )

      deltas == [] ->
        shell.info(
          "\n[budget] unchanged: #{Budget.total(counts)} accepted findings across " <>
            "#{map_size(counts)} rules."
        )

      true ->
        shell.info(
          "\n[budget] per-rule change " <>
            "(#{Budget.total(published)} → #{Budget.total(counts)} accepted findings):"
        )

        Enum.each(deltas, fn {rule, from, to} ->
          shell.info("  #{signed(to - from)}  #{rule}  (#{from} → #{to})")
        end)

        if mode == :stale do
          shell.info(
            "\n  test/corpus/findings_budget_test.exs is RED until this is published:\n" <>
              "      mix credence.corpus --update-budget"
          )
        end
    end
  end

  defp signed(n) when n > 0, do: String.pad_leading("+#{n}", 6)
  defp signed(n), do: String.pad_leading("#{n}", 6)

  # Re-publish the per-rule budget from the COMMITTED snapshot — no corpus, no
  # analysis, so it is instant and works on a machine that has never fetched.
  defp update_budget do
    counts = Budget.counts(Findings.snapshot_lines())
    published = Budget.published()

    if counts == %{} do
      Mix.raise(
        "no accepted findings in #{Path.relative_to_cwd(Findings.snapshot_path())} — refusing " <>
          "to publish an empty budget. An empty budget matching an empty snapshot is " <>
          "vacuously green, which is the one state this gate must never be in. Re-pin the " <>
          "snapshot first (`mix credence.corpus --update-snapshot`)."
      )
    end

    File.write!(Budget.budget_path(), Budget.render(counts))
    Mix.shell().info("Wrote #{map_size(counts)} rule budget(s) to #{Budget.budget_relpath()}.")
    report_budget_delta(published, counts, :published)
  end

  # The published per-rule budget, ranked — which is also the paydown ranking
  # (C13(b)). Read off the committed snapshot, so it needs no corpus.
  defp report_budget do
    shell = Mix.shell()
    counts = Budget.counts(Findings.snapshot_lines())
    published = Budget.published()
    cap = Budget.default_cap()
    ranked = Budget.rank(counts)
    {over, under} = Enum.split_with(ranked, fn {_rule, count} -> count > cap end)
    over_total = over |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    total = Budget.total(counts)

    shell.info(
      "ACCEPTED FINDINGS: #{total} across #{length(ranked)} rules " <>
        "(cap #{cap}: #{length(over)} over, #{length(under)} under)\n"
    )

    Enum.each(ranked, fn {rule, count} ->
      marker = if count > cap, do: "  OVER CAP", else: ""
      shell.info("  #{String.pad_leading(to_string(count), 5)}  #{rule}#{marker}")
    end)

    if over != [] do
      shell.info(
        "\nThe #{length(over)} rules over the cap hold #{over_total} findings " <>
          "(#{round(over_total * 100 / total)}% of the budget). Each must carry a " <>
          "@grandfathered entry in test/corpus/findings_budget_test.exs; that ledger only " <>
          "ratchets down, and a rule paid down to #{cap} must leave it."
      )
    end

    report_budget_delta(published, counts, :stale)
  end

  defp snapshot_header do
    """
    # Accepted corpus findings — over-fire regression snapshot.
    #
    # One line per accepted Pattern finding on the pinned hex packages (see
    # Credence.Corpus), formatted as:
    #
    #     <corpus-relative path>:<line>  <rule>   [ (xN) ]
    #
    # test/corpus/over_firing_test.exs asserts the LIVE set of findings equals
    # this pin, per package. A NEW line means Credence started flagging code it
    # did not before — a candidate over-fire; investigate before accepting. A
    # GONE line means a rule narrowed or was removed.
    #
    # DO NOT hand-edit. Regenerate after reviewing the test's drift report:
    #     mix credence.corpus --update-snapshot
    #
    # Why each firing rule is an accepted, behaviour-preserving suggestion (not
    # an over-fire) is documented in docs/09-corpus-over-firing-tests.md.

    """
  end

  # Returns {findings, crashes}:
  #   findings: [{package, relative_path, rule, line}]   (excludes :parse_error)
  #   crashes:  [{package, relative_path, message}]      (a rule raised on the file)
  #
  # `opts` goes straight to `Credence.Pattern.analyze/2`, so `rules: [R]` scans
  # with a single rule (docs/13 P3). The sweep is parallel over files; every
  # consumer sorts, so the report output does not depend on completion order.
  defp analyze_corpus(opts \\ []) do
    Corpus.entries()
    |> Enum.flat_map(fn {pkg, _label} -> for p <- Corpus.lib_files(pkg), do: {pkg, p} end)
    |> Task.async_stream(&analyze_file(&1, opts),
      max_concurrency: System.schedulers_online(),
      timeout: :infinity
    )
    |> Enum.reduce({[], []}, fn
      {:ok, {:findings, new}}, {f, c} -> {new ++ f, c}
      {:ok, {:crash, crash}}, {f, c} -> {f, [crash | c]}
    end)
  end

  defp analyze_file({pkg, path}, opts) do
    rel = Path.relative_to(path, Corpus.dir(pkg))
    source = File.read!(path)

    try do
      {:findings,
       for issue <- Credence.Pattern.analyze(source, opts), issue.rule != :parse_error do
         {pkg, rel, issue.rule, issue.meta[:line]}
       end}
    rescue
      e -> {:crash, {pkg, rel, e |> Exception.message() |> String.slice(0, 140)}}
    end
  end

  defp report_summary(findings, crashes) do
    shell = Mix.shell()
    shell.info("TOTAL FINDINGS: #{length(findings)}   CRASHED FILES: #{length(crashes)}\n")

    shell.info("By rule:")

    findings
    |> Enum.frequencies_by(fn {_pkg, _path, rule, _line} -> rule end)
    |> Enum.sort_by(fn {_rule, count} -> -count end)
    |> Enum.each(fn {rule, count} ->
      shell.info("  #{String.pad_leading(to_string(count), 4)}  #{rule}")
    end)

    shell.info("\nBy package:")

    findings
    |> Enum.frequencies_by(fn {pkg, _path, _rule, _line} -> pkg end)
    |> Enum.sort_by(fn {_pkg, count} -> -count end)
    |> Enum.each(fn {pkg, count} ->
      shell.info("  #{String.pad_leading(to_string(count), 4)}  #{pkg}")
    end)

    if crashes != [] do
      shell.info("\nCRASHES (a rule raised on valid code — fix these first):")

      Enum.each(crashes, fn {pkg, path, msg} ->
        shell.info("  #{pkg}/#{path}\n      #{msg}")
      end)
    end
  end

  defp report_rule(findings, rule) when is_atom(rule) do
    shell = Mix.shell()

    matches =
      findings
      |> Enum.filter(fn {_pkg, _path, r, _line} -> r == rule end)
      |> Enum.sort()

    shell.info("#{rule}: #{length(matches)} occurrence(s)\n")

    Enum.each(matches, fn {pkg, path, _rule, line} ->
      full = Path.join(Corpus.dir(pkg), path)
      src = full |> File.read!() |> String.split("\n") |> Enum.at(max(0, (line || 1) - 1))
      shell.info("#{full}:#{line}")
      shell.info("    #{String.trim(src || "")}")
    end)
  end
end
