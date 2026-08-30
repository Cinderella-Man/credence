defmodule Mix.Tasks.Credence.Mutants do
  @shortdoc "Report-only semantic-mutant kill rate per rule test triplet"

  @moduledoc """
  Semantic-mutant sweep of rule *implementations* (docs/12 **C18**, stage 1).

      MIX_ENV=test mix credence.mutants --sample 30
      MIX_ENV=test mix credence.mutants --rule no_manual_max
      MIX_ENV=test mix credence.mutants --layer syntax --cap 40 --jobs 24

  For each rule it generates deterministic first-order mutants of the rule's
  source (`Credence.Mutation` — comparison swap, ±1, `:ok`↔`:error`, boolean
  flip, capped at 40), runs **only that rule's own test files** against each
  mutant in a fresh BEAM, and writes a ledger plus a per-rule kill-rate summary.

  A **survived** mutant is a behaviour change the rule's triplet never noticed.

  ## This is report-only, on purpose

  There is no `--fail-under`, no exit-code gate, and this task is deliberately
  not wired into the suite. C18 stages the rollout — sweep → publish per-rule
  rates → fix the tail → *only then* a floor — because a floor set before the
  tail is fixed is a number nobody can act on, and docs/14 E6 showed the
  survivor list carries **equivalent mutants** (an edit that provably cannot
  change behaviour, so no test could have caught it) that must be triaged out by
  hand first. Gating on an untriaged rate would fail rules for having dead code,
  not for having weak tests.

  ## Run env

  🔴 **Must run under `MIX_ENV=test`.** The rule triplets `use
  Credence.RuleCase`, which lives in `test/support/` and is compiled only under
  `:test`. The task aborts with guidance otherwise.

  ## Options

    * `--rule NAME` — sweep this rule only (snake or Pascal). Repeatable.
    * `--layer pattern|syntax|semantic` — restrict to a layer. Repeatable.
    * `--sample N` — deterministic sample of N rules, stratified across the
      layers in proportion to their size (see `--seed`).
    * `--seed N` — sample seed (default `0`). The sample is a pure function of
      `{rule module, seed}`, so a reported sample is reproducible exactly.
    * `--cap N` — mutants per rule (default `#{Credence.Mutation.default_cap()}`).
    * `--jobs N` — rules swept in parallel (default: `System.schedulers_online()`).
    * `--timeout N` — wall-clock seconds per mutant run (default `180`).
    * `--out DIR` — ledger directory (default `tmp/mutants`, gitignored).

  ## Output

    * `DIR/mutants.tsv` — one row per mutant: layer, rule, file, line, column,
      operator, before, after, status, tests_total, tests_failed, source line.
      Tabs and newlines in the source line are escaped.
    * `DIR/summary.md` — run metadata, the corpus kill rate, per-operator rates,
      the per-rule table sorted worst-first, and the full survivor list (the
      triage queue).

  ## Reading the numbers

  `kill_rate = (killed + timeout) / (killed + survived + timeout)`. Mutants that
  did not compile (`invalid`) are **not** behaviour changes and are excluded
  from the denominator; a nonzero `error` count means the sweep itself
  misbehaved and the run should not be published. A rule whose unmutated tests
  are not green is reported as `baseline_red` and contributes no rate at all —
  a red triplet kills every mutant for the wrong reason and would otherwise
  report a perfect 1.000.
  """

  use Mix.Task

  alias Credence.Mutation
  alias Credence.Mutation.Sweep
  alias Credence.RuleHelpers
  alias Credence.RuleName

  @switches [
    rule: :keep,
    layer: :keep,
    sample: :integer,
    seed: :integer,
    cap: :integer,
    jobs: :integer,
    timeout: :integer,
    out: :string
  ]

  @behaviours %{
    pattern: Credence.Pattern.Rule,
    syntax: Credence.Syntax.Rule,
    semantic: Credence.Semantic.Rule
  }

  @layers [:pattern, :syntax, :semantic]

  @impl Mix.Task
  def run(argv) do
    ensure_test_env!()
    opts = parse_options!(argv)

    subjects = subjects(opts)

    if subjects == [] do
      Mix.raise("no rules matched --rule/--layer")
    end

    out_dir = Keyword.get(opts, :out, Path.join("tmp", "mutants"))
    File.mkdir_p!(out_dir)

    sweep_opts = [
      cap: Keyword.get(opts, :cap, Mutation.default_cap()),
      timeout_s: Keyword.get(opts, :timeout, 180),
      root: File.cwd!()
    ]

    jobs = Keyword.get(opts, :jobs, System.schedulers_online())

    unless Sweep.timeout_backstop?() do
      Mix.shell().info("[warn] `timeout(1)` not found — a hanging mutant can stall its run")
    end

    Mix.shell().info(
      "sweeping #{length(subjects)} rules, cap #{sweep_opts[:cap]}, #{jobs} parallel"
    )

    started = System.monotonic_time(:millisecond)

    reports =
      subjects
      |> Task.async_stream(&sweep_one(&1, sweep_opts),
        max_concurrency: jobs,
        timeout: :infinity,
        ordered: false
      )
      |> Enum.map(fn {:ok, report} -> report end)
      |> Enum.sort_by(& &1.subject.name)

    elapsed_ms = System.monotonic_time(:millisecond) - started

    write_ledger(out_dir, reports)
    write_summary(out_dir, reports, opts, sweep_opts, elapsed_ms)
    print_console(reports, out_dir)
  end

  @doc false
  def parse_options!(argv) do
    case OptionParser.parse(argv, strict: @switches) do
      {opts, _, []} ->
        opts

      {_, _, errors} ->
        details = Enum.map_join(errors, ", ", fn {option, value} -> "#{option} #{value}" end)
        Mix.raise("invalid option: #{details}")
    end
  end

  defp sweep_one(subject, sweep_opts) do
    report = Sweep.run(subject, sweep_opts)
    Mix.shell().info(progress_line(report))
    report
  end

  defp progress_line(%{skipped: nil} = report) do
    "  #{String.pad_trailing(report.subject.name, 48)} " <>
      "#{format_rate(report.kill_rate)}  " <>
      "killed #{report.counts.killed} survived #{report.counts.survived}" <>
      extra_counts(report.counts)
  end

  defp progress_line(report) do
    "  #{String.pad_trailing(report.subject.name, 48)} SKIPPED (#{inspect(report.skipped)})"
  end

  defp extra_counts(counts) do
    [invalid: counts.invalid, timeout: counts.timeout, error: counts.error]
    |> Enum.reject(fn {_k, v} -> v == 0 end)
    |> Enum.map_join("", fn {k, v} -> " #{k} #{v}" end)
  end

  # --- subjects ------------------------------------------------------------

  defp subjects(opts) do
    layers = layer_filter(opts)
    wanted = opts |> Keyword.get_values(:rule) |> Enum.map(&Macro.underscore/1) |> MapSet.new()

    all_snakes =
      for layer <- @layers, module <- discover(layer), into: MapSet.new() do
        RuleName.from_module(module).snake
      end

    built =
      for layer <- layers, module <- discover(layer) do
        build_subject(layer, module, all_snakes)
      end

    built
    |> then(fn list ->
      if MapSet.size(wanted) == 0, do: list, else: Enum.filter(list, &(&1.name in wanted))
    end)
    |> sample(opts)
    |> Enum.sort_by(& &1.name)
  end

  defp discover(layer), do: RuleHelpers.discover_rules(@behaviours[layer])

  defp layer_filter(opts) do
    case Keyword.get_values(opts, :layer) do
      [] -> @layers
      names -> Enum.map(names, &String.to_existing_atom/1)
    end
  end

  defp build_subject(layer, module, all_snakes) do
    derived = RuleName.from_module(module)

    %{
      name: derived.snake,
      layer: layer,
      module: module,
      source_path: derived.rule_path,
      test_files: test_files(derived, all_snakes)
    }
  end

  # `test/<layer>/<snake>_<kind>_test.exs`, plus the handful of rules whose whole
  # triplet lives in one `<snake>_test.exs`. A candidate is rejected when a
  # LONGER rule name also prefixes it — otherwise `avoid_graphemes_enum_count`
  # would swallow `avoid_graphemes_enum_count_with_predicate`'s four files and
  # report that rule's kill rate under the wrong name.
  defp test_files(derived, all_snakes) do
    (Path.wildcard("#{derived.test_dir}/#{derived.snake}_*_test.exs") ++
       Path.wildcard("#{derived.test_dir}/#{derived.snake}_test.exs"))
    |> Enum.uniq()
    |> Enum.reject(&owned_by_longer_rule?(&1, derived.snake, all_snakes))
    |> Enum.sort()
  end

  defp owned_by_longer_rule?(path, snake, all_snakes) do
    base = Path.basename(path, "_test.exs")

    Enum.any?(all_snakes, fn other ->
      other != snake and String.starts_with?(other, snake) and String.starts_with?(base, other)
    end)
  end

  # Deterministic and stratified: sample within each layer in proportion to the
  # layer's size, ranking by `phash2({module, seed})`. Same seed ⇒ same sample,
  # so a published rate names a reproducible set of rules.
  @doc false
  def sample(subjects, opts) do
    case Keyword.get(opts, :sample) do
      nil ->
        subjects

      n when n >= length(subjects) ->
        subjects

      n ->
        seed = Keyword.get(opts, :seed, 0)
        total = length(subjects)

        quotas =
          subjects
          |> Enum.group_by(& &1.layer)
          |> Enum.map(fn {layer, group} ->
            product = n * length(group)
            {layer, group, div(product, total), rem(product, total)}
          end)

        remaining = n - Enum.sum(Enum.map(quotas, &elem(&1, 2)))

        bonuses =
          quotas
          |> Enum.sort_by(fn {layer, _group, _quota, remainder} -> {-remainder, layer} end)
          |> Enum.take(remaining)
          |> MapSet.new(&elem(&1, 0))

        quotas
        |> Enum.flat_map(fn {layer, group, quota, _remainder} ->
          quota = quota + if(layer in bonuses, do: 1, else: 0)

          group
          |> Enum.sort_by(&:erlang.phash2({&1.module, seed}))
          |> Enum.take(quota)
        end)
        |> Enum.sort_by(&:erlang.phash2({&1.module, seed}))
        |> Enum.take(n)
    end
  end

  # --- ledger --------------------------------------------------------------

  @ledger_header ~w(layer rule file line column operator before after status tests_total tests_failed context)

  defp write_ledger(out_dir, reports) do
    rows =
      for report <- reports, result <- report.results do
        m = result.mutant

        Enum.join(
          [
            report.subject.layer,
            report.subject.name,
            report.subject.source_path,
            m.line,
            m.column,
            m.operator,
            m.original,
            m.replacement,
            result.status,
            result.tests_total || "",
            result.tests_failed || "",
            escape(m.context)
          ],
          "\t"
        )
      end

    File.write!(
      Path.join(out_dir, "mutants.tsv"),
      Enum.join([Enum.join(@ledger_header, "\t") | rows], "\n") <> "\n"
    )
  end

  defp escape(text) do
    text |> String.replace("\t", "\\t") |> String.replace("\n", "\\n") |> String.trim()
  end

  # --- summary -------------------------------------------------------------

  defp write_summary(out_dir, reports, opts, sweep_opts, elapsed_ms) do
    {scored, skipped} = Enum.split_with(reports, &(&1.skipped == nil))
    totals = totals(scored)

    body =
      [
        "# Semantic-mutant sweep — docs/12 C18 stage 1 (report only)\n",
        metadata(opts, sweep_opts, reports, elapsed_ms),
        "\n## Corpus\n",
        corpus_table(totals),
        "\n## By operator family\n",
        operator_table(scored),
        "\n## By rule (worst first)\n",
        rule_table(scored),
        skipped_section(skipped),
        "\n## Survivors — the triage queue\n",
        survivor_table(scored)
      ]
      |> Enum.join("\n")

    File.write!(Path.join(out_dir, "summary.md"), body)
  end

  defp metadata(opts, sweep_opts, reports, elapsed_ms) do
    """
    | field | value |
    | ----- | ----- |
    | generated | #{DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()} |
    | elixir | #{System.version()} / OTP #{System.otp_release()} |
    | rules swept | #{length(reports)} |
    | cap | #{sweep_opts[:cap]} |
    | sample / seed | #{Keyword.get(opts, :sample, "all")} / #{Keyword.get(opts, :seed, 0)} |
    | wall clock | #{Float.round(elapsed_ms / 1000, 1)} s |
    | operators | #{Enum.map_join(Mutation.operators(), ", ", &to_string/1)} |
    """
  end

  defp totals(scored) do
    Enum.reduce(scored, %{killed: 0, survived: 0, timeout: 0, invalid: 0, error: 0}, fn r, acc ->
      Map.merge(acc, r.counts, fn _k, a, b -> a + b end)
    end)
  end

  defp corpus_table(totals) do
    """
    | metric | value |
    | ------ | ----- |
    | **kill rate** | **#{format_rate(Sweep.kill_rate(totals))}** |
    | killed | #{totals.killed} |
    | survived | #{totals.survived} |
    | timeout (counted as killed) | #{totals.timeout} |
    | invalid — did not compile, excluded | #{totals.invalid} |
    | error — no verdict, excluded | #{totals.error} |
    """
  end

  defp operator_table(scored) do
    by_operator =
      for report <- scored, result <- report.results do
        {result.mutant.operator, result.status}
      end
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    rows =
      for operator <- Mutation.operators(), statuses = Map.get(by_operator, operator, []) do
        counts =
          Enum.reduce(statuses, %{killed: 0, survived: 0, timeout: 0, invalid: 0, error: 0}, fn s,
                                                                                                acc ->
            Map.update!(acc, s, &(&1 + 1))
          end)

        "| #{operator} | #{format_rate(Sweep.kill_rate(counts))} | #{counts.killed} | #{counts.survived} | #{counts.invalid} |"
      end

    Enum.join(
      [
        "| operator | kill rate | killed | survived | invalid |",
        "| --- | --- | --- | --- | --- |"
      ] ++
        rows,
      "\n"
    ) <> "\n"
  end

  defp rule_table(scored) do
    rows =
      scored
      |> Enum.sort_by(fn r -> {r.kill_rate || 2.0, r.subject.name} end)
      |> Enum.map(fn r ->
        "| #{r.subject.name} | #{r.subject.layer} | #{format_rate(r.kill_rate)} | " <>
          "#{r.counts.killed} | #{r.counts.survived} | #{r.counts.invalid} | " <>
          "#{length(r.subject.test_files)} | #{baseline_total(r.baseline)} |"
      end)

    Enum.join(
      [
        "| rule | layer | kill rate | killed | survived | invalid | test files | tests |",
        "| --- | --- | --- | --- | --- | --- | --- | --- |"
      ] ++ rows,
      "\n"
    ) <> "\n"
  end

  defp skipped_section([]), do: ""

  defp skipped_section(skipped) do
    rows =
      Enum.map(skipped, fn r ->
        "| #{r.subject.name} | #{r.subject.layer} | #{inspect(r.skipped)} | #{inspect(r.baseline)} |"
      end)

    "\n## Skipped — contribute no rate\n\n" <>
      Enum.join(
        ["| rule | layer | reason | baseline |", "| --- | --- | --- | --- |"] ++ rows,
        "\n"
      ) <> "\n"
  end

  @doc false
  def survivor_table(scored) do
    rows =
      for report <- scored,
          result <- report.results,
          result.status == :survived do
        m = result.mutant

        "| #{report.subject.name} | #{report.subject.source_path}:#{m.line}:#{m.column} | " <>
          "#{m.operator} | `#{m.original}` → `#{m.replacement}` | `#{escape_markdown_table(m.context)}` |"
      end

    case rows do
      [] ->
        "No survivors.\n"

      rows ->
        Enum.join(
          [
            "Each row is a behaviour change the rule's own tests did not notice —",
            "**or** an equivalent mutant (docs/14 E6). Triage before acting.\n",
            "| rule | site | operator | mutation | source line |",
            "| --- | --- | --- | --- | --- |"
          ] ++ rows,
          "\n"
        ) <> "\n"
    end
  end

  defp escape_markdown_table(text) do
    text |> escape() |> String.replace("|", "\\|")
  end

  defp baseline_total({:green, total}), do: total
  defp baseline_total(other), do: inspect(other)

  defp format_rate(nil), do: "—"
  defp format_rate(rate), do: :erlang.float_to_binary(rate, decimals: 3)

  # --- console -------------------------------------------------------------

  defp print_console(reports, out_dir) do
    {scored, skipped} = Enum.split_with(reports, &(&1.skipped == nil))
    totals = totals(scored)

    Mix.shell().info("")
    Mix.shell().info("corpus kill rate: #{format_rate(Sweep.kill_rate(totals))}")

    Mix.shell().info(
      "killed #{totals.killed} · survived #{totals.survived} · timeout #{totals.timeout} · " <>
        "invalid #{totals.invalid} · error #{totals.error} · skipped rules #{length(skipped)}"
    )

    Mix.shell().info("ledger: #{Path.join(out_dir, "mutants.tsv")}")
    Mix.shell().info("summary: #{Path.join(out_dir, "summary.md")}")

    if totals.error > 0 do
      Mix.shell().info(
        "[warn] #{totals.error} mutants produced no verdict — do not publish this run"
      )
    end
  end

  defp ensure_test_env! do
    unless Mix.env() == :test do
      Mix.raise("""
      mix credence.mutants must run under MIX_ENV=test.

      Rule triplets `use Credence.RuleCase`, which lives in test/support and is
      compiled only in the :test environment.

          MIX_ENV=test mix credence.mutants --sample 30
      """)
    end
  end
end
