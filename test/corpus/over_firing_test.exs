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

  ## Drift messages are self-contained

  Because the consumer of a failure is often an AI agent, each NEW finding is
  expanded inline with everything needed to judge the over-fire without opening
  the file or re-running anything: the rule's own complaint, the offending source
  with surrounding context, the exact rewrite *that one rule* would make (a
  line-numbered diff of the hunk at the finding, plus a note if the fix also
  touches other lines), and the before/after **Sourceror** AST of that hunk — the
  same form the rules match on.
  """
  use ExUnit.Case, async: true

  @moduletag :corpus
  # A few corpus entries are very large (beefy app repos / generated SDKs), so a
  # single per-entry test can exceed ExUnit's default 60s. Give them headroom.
  @moduletag timeout: 180_000

  alias Credence.Corpus
  alias Credence.Corpus.{Findings, Progress}
  alias Credence.{Pattern, RuleHelpers, RuleName}

  # Emit a "Validated Q out of P files" line every this-many validated files.
  @progress_step 500

  # Lines of source shown on each side of an offending line.
  @context 3
  # Cap on rendered diff rows so a whole-module fix can't flood the message.
  @max_diff_lines 30
  # AST is shown only for small changed spans, where it disambiguates the
  # construct; for a large multi-line span it just echoes the diff, so skip it.
  @max_ast_lines 4

  setup_all do
    Corpus.ensure_fetched!()

    total_files =
      Corpus.entries()
      |> Enum.map(fn {name, _label} -> length(Corpus.lib_files(name)) end)
      |> Enum.sum()

    rule_count = length(Pattern.default_rules())
    whitelist_count = length(Findings.snapshot_lines())

    IO.puts(
      "\n  [corpus] Corpus test validating against #{total_files} files across " <>
        "#{length(Corpus.packages())} hex packages + #{length(Corpus.repos())} repos, " <>
        "with a whitelist of #{whitelist_count} accepted findings (#{rule_count} rules)."
    )

    Progress.start(:analyze, total_files, @progress_step, "Validated", "files")
    on_exit(fn -> Progress.stop(:analyze) end)
    :ok
  end

  for {pkg, version} <- Credence.Corpus.entries() do
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
    #{explain_added(added)}

    GONE — pinned but no longer firing (a rule narrowed / was removed — fine to re-pin):
    #{bullets(removed)}

    If these changes are expected, re-pin with:
        mix credence.corpus --update-snapshot
    """
  end

  defp bullets([]), do: "  (none)"
  defp bullets(lines), do: "  " <> Enum.join(lines, "\n  ")

  defp explain_added([]), do: "  (none)"
  defp explain_added(lines), do: Enum.map_join(lines, "\n\n", &explain/1)

  # A rich, self-contained explanation for one NEW finding. Every step is
  # best-effort: anything that cannot be resolved degrades to the bare line
  # rather than crashing the failure report.
  defp explain(finding) do
    with {:ok, rel, lineno, rule} <- parse_finding(finding),
         {:ok, source} <- File.read(Path.join(Corpus.root(), rel)) do
      module = rule_module(rule)

      compact([
        "  • #{finding}",
        detail("why", rule_complaint(source, module, lineno)),
        detail("offending code (#{rel})", source_excerpt(source, lineno)),
        rewrite_section(source, module, lineno)
      ])
    else
      _ -> "  • #{finding}"
    end
  rescue
    e -> "  • #{finding}\n      (detail unavailable: #{Exception.message(e)})"
  end

  # "<pkg>/<path>:<line>  <rule>  [(xN)]" -> {:ok, rel, line, rule} | :error
  defp parse_finding(finding) do
    case Regex.run(~r/^(\S+):(\d+)\s+([a-z0-9_]+)/, finding) do
      [_, rel, line, rule] -> {:ok, rel, String.to_integer(line), rule}
      _ -> :error
    end
  end

  # Resolve a rule's snake name to its module, but only if it is a real, loaded
  # Pattern rule with a fix.
  defp rule_module(rule) do
    module = RuleName.derive(rule, :pattern).rule_module

    if Code.ensure_loaded?(module) and function_exported?(module, :fix_patches, 2),
      do: module,
      else: nil
  rescue
    _ -> nil
  end

  defp rule_complaint(_source, nil, _lineno), do: nil

  defp rule_complaint(source, module, lineno) do
    source
    |> Pattern.analyze(rules: [module])
    |> Enum.find(&(&1.meta[:line] == lineno))
    |> case do
      %{message: message} when is_binary(message) -> message
      _ -> nil
    end
  end

  defp source_excerpt(source, lineno) do
    lines = String.split(source, "\n")
    lo = max(lineno - @context, 1)
    hi = min(lineno + @context, length(lines))
    width = hi |> Integer.to_string() |> String.length()

    Enum.map_join(lo..hi, "\n", fn n ->
      marker = if n == lineno, do: ">", else: " "
      num = n |> Integer.to_string() |> String.pad_leading(width)
      "#{marker} #{num} | #{Enum.at(lines, n - 1)}"
    end)
  end

  defp rewrite_section(_source, nil, _lineno),
    do: detail("would rewrite to", "(rule module not resolvable)")

  defp rewrite_section(source, module, lineno) do
    case safe_fix(module, source) do
      ^source ->
        detail("would rewrite to", "(check-only — rule flags but applies no fix)")

      fixed ->
        hunks = to_hunks(source, fixed)
        hunk = pick_hunk(hunks, lineno)

        compact([
          detail("would rewrite to (this rule only)", hunk_diff(hunk)),
          other_changes_note(hunks, hunk),
          detail("Sourceror AST of the change", hunk_ast(hunk))
        ])
    end
  end

  defp safe_fix(module, source) do
    RuleHelpers.apply_rule_fix(module, source)
  rescue
    _ -> source
  end

  # Group the line diff into hunks (maximal runs of consecutive changed lines),
  # each tagged with the original line numbers of its deletions. This lets the
  # report focus on the hunk *at the finding* rather than unrelated edits
  # elsewhere — e.g. a whole-module rule that also reformats other lines.
  defp to_hunks(before, fixed) do
    diff = List.myers_difference(String.split(before, "\n"), String.split(fixed, "\n"))

    {hunks, current, _bline} =
      Enum.reduce(diff, {[], nil, 1}, fn
        {:eq, ls}, {hs, cur, bline} ->
          {close_hunk(hs, cur), nil, bline + length(ls)}

        {:del, ls}, {hs, cur, bline} ->
          cur = cur || %{start: bline, dels: [], inss: []}
          dels = cur.dels ++ Enum.map(Enum.with_index(ls, bline), fn {l, n} -> {n, l} end)
          {hs, %{cur | dels: dels}, bline + length(ls)}

        {:ins, ls}, {hs, cur, bline} ->
          cur = cur || %{start: bline, dels: [], inss: []}
          {hs, %{cur | inss: cur.inss ++ ls}, bline}
      end)

    close_hunk(hunks, current)
  end

  defp close_hunk(hunks, nil), do: hunks
  defp close_hunk(hunks, hunk), do: hunks ++ [hunk]

  # The hunk whose deletions cover the finding line, else the nearest one.
  defp pick_hunk([], _lineno), do: nil

  defp pick_hunk(hunks, lineno) do
    Enum.find(hunks, fn h -> Enum.any?(h.dels, fn {n, _} -> n == lineno end) end) ||
      Enum.min_by(hunks, fn h -> abs(h.start - lineno) end)
  end

  # A line-numbered diff of the focused hunk. `-` rows carry the original line
  # number; `+` rows are the replacement.
  defp hunk_diff(nil), do: nil

  defp hunk_diff(%{dels: dels, inss: inss}) do
    del_rows = Enum.map(dels, fn {n, l} -> "- #{n} | #{l}" end)
    ins_rows = Enum.map(inss, &"+     | #{&1}")
    cap(del_rows ++ ins_rows)
  end

  # When the fix touches lines outside the focused hunk (typically a whole-module
  # transform that also reformats), say so rather than hide it.
  defp other_changes_note(hunks, hunk) do
    elsewhere = hunks |> Enum.reject(&(&1 == hunk)) |> Enum.map(&hunk_size/1) |> Enum.sum()

    if elsewhere > 0,
      do:
        detail("note", "this rule's fix also changes #{elsewhere} line(s) elsewhere in the file"),
      else: nil
  end

  defp hunk_size(%{dels: dels, inss: inss}), do: length(dels) + length(inss)

  # Sourceror AST of the focused hunk — the form the rules actually operate on.
  # Shown only when both sides are small and parse cleanly on their own.
  defp hunk_ast(nil), do: nil

  defp hunk_ast(%{dels: dels, inss: inss}) do
    before = Enum.map(dels, &elem(&1, 1))

    with true <- small?(before) and small?(inss),
         {:ok, before_str} <- ast_side(before),
         {:ok, after_str} <- ast_side(inss) do
      "before: #{before_str}\nafter:  #{after_str}"
    else
      _ -> nil
    end
  end

  defp small?(lines), do: length(lines) <= @max_ast_lines

  # Parse one side of a hunk to its Sourceror AST. A pipe segment (`|> foo()`)
  # is not valid standalone, so strip a leading `|>` to recover the changed call.
  defp ast_side([]), do: {:ok, "(none)"}

  defp ast_side(lines) do
    src =
      lines
      |> Enum.join("\n")
      |> String.trim()
      |> String.replace_leading("|>", "")
      |> String.trim()

    case Sourceror.parse_string(src) do
      {:ok, ast} -> {:ok, inspect(ast)}
      _ -> :error
    end
  end

  defp cap(rows) when length(rows) <= @max_diff_lines, do: Enum.join(rows, "\n")

  defp cap(rows) do
    shown = Enum.take(rows, @max_diff_lines)
    Enum.join(shown, "\n") <> "\n… (#{length(rows) - @max_diff_lines} more changed lines)"
  end

  # label/body block; a nil or empty body drops the block entirely.
  defp detail(_label, nil), do: nil
  defp detail(_label, ""), do: nil
  defp detail(label, body), do: "      #{label}:\n" <> indent(body, 8)

  defp indent(text, n) do
    pad = String.duplicate(" ", n)
    text |> String.split("\n") |> Enum.map_join("\n", &(pad <> &1))
  end

  defp compact(parts), do: parts |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join("\n")
end
