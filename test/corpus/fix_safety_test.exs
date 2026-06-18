defmodule Credence.Corpus.FixSafetyTest do
  @moduledoc """
  Fix-safety layer over the real-world corpus.

  The over-firing test (`test/corpus/over_firing_test.exs`) pins which *lines*
  Credence flags (`Credence.Pattern.analyze/2`) but **never applies a fix**, so it
  is structurally blind to what the fixes actually produce. This layer closes that
  gap: it applies each accepted finding's single-rule fix to the real corpus
  source and asserts the fix does no collateral damage.

  ## Invariant: a fix never drops a source comment

  Comments live in the source, not the AST. A rule that builds or re-renders a
  fresh AST for its replacement (via `Sourceror.to_string/1`) silently loses any
  comment that sat inside the construct it rewrote — real information loss the
  user never asked for. This test re-extracts every comment before and after the
  fix (`Code.string_to_quoted_with_comments/1`) and fails, naming the rule, file,
  finding line(s), and the exact comment text, if any comment disappears.

  Scoped to the accepted findings (so it tracks the same set the snapshot pins).
  Tagged `:corpus`; skip with `mix test --exclude corpus`.
  """
  use ExUnit.Case, async: true

  @moduletag :corpus
  # Large entries (beefy app repos) can exceed ExUnit's default 60s per test;
  # applying fixes is heavier than analysis, so give generous headroom.
  @moduletag timeout: 180_000

  alias Credence.{Corpus, Pattern, RuleHelpers, RuleName}

  setup_all do
    Corpus.ensure_fetched!()
    :ok
  end

  for {pkg, version} <- Corpus.entries() do
    test "fixes on #{pkg} v#{version} drop no source comments" do
      pkg = unquote(pkg)
      violations = comment_loss_violations(pkg)
      assert violations == [], report(pkg, unquote(version), violations)
    end

    test "fixes on #{pkg} v#{version} introduce no mangled `__`-prefixed variable" do
      pkg = unquote(pkg)
      violations = var_mangling_violations(pkg)
      assert violations == [], mangling_report(pkg, unquote(version), violations)
    end

    test "fixes on #{pkg} v#{version} reformat no unrelated code (over-reach)" do
      pkg = unquote(pkg)
      violations = over_reach_violations(pkg)
      assert violations == [], over_reach_report(pkg, unquote(version), violations)
    end
  end

  # A fix must change CODE, never merely re-wrap unrelated lines. After
  # mix-format-normalizing both sides, a replacement hunk whose deleted and
  # inserted text are identical except for whitespace is pure reformatting the
  # fix had no business touching (e.g. collapsing an unrelated multi-line
  # `@attr` keyword list onto one line). A real change differs in tokens, so it
  # is not flagged.
  defp over_reach_violations(pkg) do
    pkg
    |> findings_by_file_rule()
    |> Enum.flat_map(fn {{rel, rule, path}, lines} ->
      src = File.read!(path)
      fixed = safe_fix(rule, src)

      case rewrap_hunks(src, fixed) do
        [] -> []
        hunks -> [%{rule: rule, rel: rel, lines: Enum.sort(lines), hunks: hunks}]
      end
    end)
  end

  # An eq run longer than this between two changed hunks splits them into
  # separate "change regions": code far from any real change.
  @region_gap 3

  # A re-wrap hunk (deleted and inserted text token-identical, differing only in
  # whitespace) is over-reach ONLY when it stands alone — in a region of the diff
  # with no real token change. A re-wrap that shares a change region with a real
  # token change is a legitimate consequence of that change: rewriting `case`→
  # `if` (a real token change) dedents the branch body one level, so mix-format
  # re-wraps it — unavoidable for any correct fix. The gratuitous case the check
  # targets (re-rendering a parent reformats an *unrelated* node) lands in its
  # own region, far from the real edit, and is still flagged.
  defp rewrap_hunks(src, fixed) do
    fin = String.split(fmt(src), "\n")
    fout = String.split(fmt(fixed), "\n")

    fin
    |> List.myers_difference(fout)
    |> change_events()
    |> regions()
    |> Enum.flat_map(&over_reach_in_region/1)
  end

  # Flatten the diff into a stream of `{:gap, n}` (an eq run of n lines),
  # `{:real, del}` (tokens actually changed — incl. a bare deletion/insertion),
  # and `{:reflow, del}` (token-identical, whitespace-only). Pure-reindent hunks
  # (same line count, equal after trimming leading whitespace) are dropped: a
  # leading-indent shift is always a legitimate depth change.
  defp change_events([]), do: []
  defp change_events([{:eq, ls} | rest]), do: [{:gap, length(ls)} | change_events(rest)]

  defp change_events([{:del, d}, {:ins, i} | rest]) do
    cond do
      nospace(d) == nospace(i) and reindent_only?(d, i) -> change_events(rest)
      nospace(d) == nospace(i) -> [{:reflow, d} | change_events(rest)]
      true -> [{:real, d} | change_events(rest)]
    end
  end

  defp change_events([{:del, d} | rest]), do: [{:real, d} | change_events(rest)]
  defp change_events([{:ins, _} | rest]), do: [{:real, []} | change_events(rest)]

  # Group events into regions, splitting on any eq gap longer than @region_gap.
  defp regions(events) do
    {regions, current} =
      Enum.reduce(events, {[], []}, fn
        {:gap, n}, {regions, current} when n > @region_gap -> {[Enum.reverse(current) | regions], []}
        {:gap, _}, acc -> acc
        ev, {regions, current} -> {regions, [ev | current]}
      end)

    Enum.reverse([Enum.reverse(current) | regions]) |> Enum.reject(&(&1 == []))
  end

  # A region with a real token change makes its re-wraps legitimate; a region of
  # pure re-wraps reformatted code with no real edit, which is over-reach.
  defp over_reach_in_region(region) do
    if Enum.any?(region, &match?({:real, _}, &1)) do
      []
    else
      for {:reflow, del} <- region, do: Enum.map_join(del, " ⏎ ", &String.trim/1)
    end
  end

  # A pure *leading-indentation* shift (same line count, each line equal after
  # trimming leading whitespace) is always a legitimate depth change.
  defp reindent_only?(del, ins) do
    length(del) == length(ins) and
      Enum.all?(Enum.zip(del, ins), fn {d, i} ->
        String.trim_leading(d) == String.trim_leading(i)
      end)
  end

  defp nospace(lines), do: lines |> Enum.join("\n") |> String.replace(~r/\s+/, "")

  defp fmt(source) do
    IO.iodata_to_binary(Code.format_string!(source))
  rescue
    _ -> source
  end

  # A fix that re-underscores an already-unused `_x` param into `__x` is a bug
  # (`__x` is not a conventional unused name and reads as a typo). Flag any
  # `__`-prefixed variable the fix introduces that was not already in the source.
  defp var_mangling_violations(pkg) do
    pkg
    |> findings_by_file_rule()
    |> Enum.flat_map(fn {{rel, rule, path}, lines} ->
      src = File.read!(path)
      fixed = safe_fix(rule, src)

      case introduced_mangled_vars(src, fixed) do
        [] -> []
        mangled -> [%{rule: rule, rel: rel, lines: Enum.sort(lines), mangled: mangled}]
      end
    end)
  end

  defp introduced_mangled_vars(src, fixed) do
    before = MapSet.new(var_names(src))

    fixed
    |> var_names()
    |> Enum.filter(&mangled_var?/1)
    |> Enum.reject(&MapSet.member?(before, &1))
    |> Enum.uniq()
  end

  defp var_names(source) do
    case Code.string_to_quoted(source) do
      {:ok, ast} ->
        {_ast, acc} =
          Macro.prewalk(ast, [], fn
            {name, _meta, ctx} = node, acc when is_atom(name) and is_atom(ctx) ->
              {node, [name | acc]}

            node, acc ->
              {node, acc}
          end)

        acc

      _ ->
        []
    end
  end

  # `__foo` (double-underscore, lowercase, no trailing `__`) — the mangling shape.
  # Excludes the `__MODULE__`/`__ENV__`/… special forms (they end in `__`).
  defp mangled_var?(name) do
    s = Atom.to_string(name)
    String.starts_with?(s, "__") and not String.ends_with?(s, "__")
  end

  # One entry per (file, rule) whose single-rule fix loses a comment.
  defp comment_loss_violations(pkg) do
    pkg
    |> findings_by_file_rule()
    |> Enum.flat_map(fn {{rel, rule, path}, lines} ->
      src = File.read!(path)
      fixed = safe_fix(rule, src)

      case lost_comments(src, fixed) do
        [] -> []
        lost -> [%{rule: rule, rel: rel, lines: Enum.sort(lines), lost: lost}]
      end
    end)
  end

  # {rel, rule, abs_path} => [finding_line, ...] for every Pattern finding.
  defp findings_by_file_rule(pkg) do
    pkg
    |> Corpus.lib_files()
    |> Enum.flat_map(fn path ->
      source = File.read!(path)
      rel = Path.relative_to(path, Corpus.root())

      for issue <- Pattern.analyze(source), issue.rule != :parse_error do
        {{rel, issue.rule, path}, issue.meta[:line]}
      end
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp safe_fix(rule, src) do
    module = RuleName.derive(to_string(rule), :pattern).rule_module
    RuleHelpers.apply_rule_fix(module, src)
  rescue
    _ -> src
  end

  # Comment texts present in `before` more often than in `after_` — i.e. dropped.
  defp lost_comments(before, after_) do
    counts_before = comment_counts(before)
    counts_after = comment_counts(after_)

    for {text, n} <- counts_before, n > Map.get(counts_after, text, 0), do: text
  end

  defp comment_counts(source) do
    case Code.string_to_quoted_with_comments(source) do
      {:ok, _ast, comments} -> comments |> Enum.map(&String.trim(&1.text)) |> Enum.frequencies()
      _ -> %{}
    end
  end

  defp report(pkg, version, violations) do
    body =
      Enum.map_join(violations, "\n", fn v ->
        "  • #{v.rel}:#{Enum.join(v.lines, ",")}  #{v.rule}\n" <>
          Enum.map_join(v.lost, "\n", &"      dropped comment: #{&1}")
      end)

    """
    #{length(violations)} fix(es) on #{pkg} v#{version} silently drop a source comment
    (the replacement AST does not carry the comment that sat in the rewritten
    construct). Each line is a rule whose fix must preserve the comment:

    #{body}
    """
  end

  defp mangling_report(pkg, version, violations) do
    body =
      Enum.map_join(violations, "\n", fn v ->
        "  • #{v.rel}:#{Enum.join(v.lines, ",")}  #{v.rule}\n" <>
          "      introduced variable(s): #{Enum.join(v.mangled, ", ")}"
      end)

    """
    #{length(violations)} fix(es) on #{pkg} v#{version} introduce a mangled `__`-prefixed
    variable (an already-unused `_x` re-underscored into `__x`):

    #{body}
    """
  end

  defp over_reach_report(pkg, version, violations) do
    body =
      Enum.map_join(violations, "\n", fn v ->
        "  • #{v.rel}:#{Enum.join(v.lines, ",")}  #{v.rule}\n" <>
          Enum.map_join(v.hunks, "\n", &"      re-wrapped (unchanged) code: #{&1}")
      end)

    """
    #{length(violations)} fix(es) on #{pkg} v#{version} reformat code they did not change
    (a hunk whose text is identical except for whitespace — the fix re-wrapped a
    node it had no business touching). Each is a rule whose fix must be surgical:

    #{body}
    """
  end
end
