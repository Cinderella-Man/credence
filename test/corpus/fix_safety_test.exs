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

  alias Credence.{Corpus, Pattern, RuleHelpers, RuleName}

  setup_all do
    Corpus.ensure_fetched!()
    :ok
  end

  for {pkg, version} <- Corpus.packages() do
    test "fixes on #{pkg} v#{version} drop no source comments" do
      pkg = unquote(pkg)
      violations = comment_loss_violations(pkg)
      assert violations == [], report(pkg, unquote(version), violations)
    end
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
end
