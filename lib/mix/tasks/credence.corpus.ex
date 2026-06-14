defmodule Mix.Tasks.Credence.Corpus do
  @shortdoc "Run Credence's Pattern phase over the real-world corpus and report findings"

  @moduledoc """
  Runs `Credence.Pattern.analyze/1` over the `lib/` source of the pinned popular
  hex packages in `corpus/` (see `Credence.Corpus`) and reports what Credence
  flags — the over-firing signal.

      mix credence.corpus               # summary: totals, crashes, counts by rule + package
      mix credence.corpus <rule>        # every occurrence of <rule> with file:line + source
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
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("compile")

    case args do
      ["--update-snapshot"] ->
        Credence.Corpus.ensure_fetched!()
        update_snapshot()

      _ ->
        require_corpus!()
        {findings, crashes} = analyze_corpus()

        case args do
          [] -> report_summary(findings, crashes)
          [rule] -> report_rule(findings, rule)
          _ -> Mix.raise("usage: mix credence.corpus [rule_name | --update-snapshot]")
        end
    end
  end

  defp require_corpus! do
    if Enum.all?(Credence.Corpus.packages(), fn {pkg, _} -> not Credence.Corpus.fetched?(pkg) end) do
      Mix.raise(
        "No corpus found in #{Credence.Corpus.root()}/. " <>
          "Run `mix credence.corpus.fetch` first (or `mix test`)."
      )
    end
  end

  defp update_snapshot do
    lines = Credence.Corpus.Findings.all()
    path = Credence.Corpus.Findings.snapshot_path()
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
  defp analyze_corpus do
    Enum.reduce(Credence.Corpus.packages(), {[], []}, fn {pkg, _version}, acc ->
      pkg
      |> Credence.Corpus.lib_files()
      |> Enum.reduce(acc, fn path, {f, c} ->
        rel = Path.relative_to(path, Credence.Corpus.dir(pkg))
        source = File.read!(path)

        try do
          new =
            for issue <- Credence.Pattern.analyze(source), issue.rule != :parse_error do
              {pkg, rel, issue.rule, issue.meta[:line]}
            end

          {new ++ f, c}
        rescue
          e -> {f, [{pkg, rel, e |> Exception.message() |> String.slice(0, 140)} | c]}
        end
      end)
    end)
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

  defp report_rule(findings, rule_str) do
    rule = String.to_atom(rule_str)
    shell = Mix.shell()

    matches =
      findings
      |> Enum.filter(fn {_pkg, _path, r, _line} -> r == rule end)
      |> Enum.sort()

    shell.info("#{rule}: #{length(matches)} occurrence(s)\n")

    Enum.each(matches, fn {pkg, path, _rule, line} ->
      full = Path.join(Credence.Corpus.dir(pkg), path)
      src = full |> File.read!() |> String.split("\n") |> Enum.at(max(0, (line || 1) - 1))
      shell.info("#{full}:#{line}")
      shell.info("    #{String.trim(src || "")}")
    end)
  end
end
