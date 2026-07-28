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

  Fetch the corpus first with `mix credence.corpus.fetch` (or run `mix test`,
  which auto-fetches). A *crash* (a rule raising on valid code) is worse than a
  finding and is reported separately.

  The summary/`<rule>` modes report the *raw* Pattern findings. The over-firing
  test (`test/corpus/over_firing_test.exs`) instead compares the findings,
  resolved to `<path>:<line>  <rule>` identities, against the committed snapshot
  `test/corpus/accepted_findings.txt`. `--update-snapshot` regenerates that
  snapshot from the current corpus — run it after reviewing the drift the test
  reports, to accept the new set.

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
  alias Credence.Corpus.{Findings, Progress}

  # Emit a progress line every this-many scanned files during a scoped sweep.
  @progress_step 5000

  # Lines of source shown for each drifted finding.
  @context 1

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("compile")

    {opts, rest, invalid} =
      OptionParser.parse(args, strict: [update_snapshot: :boolean, only_rule: :string])

    cond do
      invalid != [] ->
        Mix.raise("unknown option #{inspect(Enum.map(invalid, &elem(&1, 0)))}.\n#{usage()}")

      opts[:update_snapshot] && rest != [] ->
        Mix.raise("--update-snapshot takes no other arguments.\n#{usage()}")

      opts[:update_snapshot] ->
        Corpus.ensure_fetched!()
        update_snapshot()

      opts[:only_rule] && rest != [] ->
        Mix.raise("--only-rule takes no other arguments.\n#{usage()}")

      opts[:only_rule] ->
        require_corpus!()
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
    "usage: mix credence.corpus [<rule> | --only-rule <rule> | --update-snapshot]"
  end

  defp require_corpus! do
    if Enum.all?(Corpus.entries(), fn {name, _} -> not Corpus.fetched?(name) end) do
      Mix.raise(
        "No corpus found in #{Corpus.root()}/. " <>
          "Run `mix credence.corpus.fetch` first (or `mix test`)."
      )
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
    lines = Findings.all()
    path = Findings.snapshot_path()
    File.write!(path, snapshot_header() <> Enum.join(lines, "\n") <> "\n")

    Mix.shell().info(
      "Wrote #{length(lines)} accepted finding(s) to #{Path.relative_to_cwd(path)}."
    )
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
