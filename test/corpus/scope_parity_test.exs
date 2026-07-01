defmodule Credence.Corpus.ScopeParityTest do
  @moduledoc """
  Scope-parity layer over the real-world corpus.

  A rule's FIX must fire exactly where its CHECK fires — they select the same
  things. Neither sibling corpus test catches a fix that is BROADER than its
  check: the over-firing test (`over_firing_test.exs`) pins only CHECK output, so
  a fix-only over-reach is invisible; the fix-safety test (`fix_safety_test.exs`)
  applies fixes only at *already-flagged* findings, so it never exercises a
  check-clean file. This layer closes that gap.

  ## Invariant

  For every Pattern rule and every corpus file, if the rule's check is clean
  (`rule.check(ast, []) == []`) then the rule's fix must NET no change
  (`apply_rule_fix(rule, src) == src`). A violation — the fix rewrites code the
  check leaves clean — means the fix selects something the check does not. The
  cure is always the same: have check and fix share ONE scope predicate.

  We probe `fix_patches/2` first (cheap) and only confirm with the full
  `apply_rule_fix` pipeline (which re-parses) for the rare candidate, so a clean
  corpus costs ~one extra analysis pass.

  Tagged `:corpus`; skip with `mix test --exclude corpus`.
  """
  use ExUnit.Case, async: true

  @moduletag :corpus
  # Per-package work is 146 rules x N files; the beefy repos need headroom.
  @moduletag timeout: 300_000

  alias Credence.{Corpus, Pattern, RuleHelpers}
  alias Credence.Corpus.Progress

  @rules Pattern.default_rules()
  @progress_step 500
  # Source lines shown on each side of the offending change in a failure.
  @context 2

  setup_all do
    Corpus.ensure_fetched!()

    total_files =
      Corpus.entries()
      |> Enum.map(fn {name, _label} -> length(Corpus.lib_files(name)) end)
      |> Enum.sum()

    IO.puts(
      "\n  [corpus] Scope-parity: #{length(@rules)} rules — a fix must change code " <>
        "ONLY where its check flags, across #{total_files} files."
    )

    Progress.start(:scope, total_files, @progress_step, "Scope-checked", "files")
    on_exit(fn -> Progress.stop(:scope) end)
    :ok
  end

  for {pkg, version} <- Corpus.entries() do
    test "fixes on #{pkg} v#{version} fire only where the check flags" do
      violations = scope_violations(unquote(pkg))
      assert violations == [], report(unquote(pkg), unquote(version), violations)
    end
  end

  # Every (file, rule) where the check is clean yet the fix nets a change.
  defp scope_violations(pkg) do
    pkg
    |> Corpus.lib_files()
    |> Enum.flat_map(fn path ->
      src = File.read!(path)

      violations =
        case Sourceror.parse_string(src) do
          {:ok, ast} -> Enum.flat_map(@rules, &rule_violation(&1, ast, src, path))
          _ -> []
        end

      Progress.tick(:scope)
      violations
    end)
  end

  defp rule_violation(rule, ast, src, path) do
    # Cheap gates first; only the rare candidate pays for `apply_rule_fix`.
    if check_clean?(rule, ast) and fix_produces_patches?(rule, ast, src) do
      case apply_fix(rule, src) do
        ^src ->
          []

        fixed ->
          [
            %{
              rule: RuleHelpers.rule_name(rule),
              rel: Path.relative_to(path, Corpus.root()),
              src: src,
              fixed: fixed
            }
          ]
      end
    else
      []
    end
  end

  # The rule's OWN check (not `Pattern.analyze`, which filters its default set by
  # assumptions and would report a flagged file as clean). A check that raises on
  # exotic corpus code is treated as "not clean" — conservative, never a false
  # violation.
  defp check_clean?(rule, ast) do
    rule.check(ast, []) == []
  rescue
    _ -> false
  end

  defp fix_produces_patches?(rule, ast, src) do
    case rule.fix_patches(ast, source: src) do
      patches when is_list(patches) -> patches != []
      _ -> false
    end
  rescue
    _ -> false
  end

  defp apply_fix(rule, src) do
    RuleHelpers.apply_rule_fix(rule, src)
  rescue
    _ -> src
  end

  # ── failure report ────────────────────────────────────────────────

  defp report(pkg, version, violations) do
    body = Enum.map_join(violations, "\n\n", &explain/1)

    """
    #{length(violations)} fix(es) on #{pkg} v#{version} change code their OWN check
    leaves clean — the fix's scope is broader than the check's. A rule's fix must
    fire only where its check flags. Make check and fix share one scope predicate.

    #{body}
    """
  end

  defp explain(%{rule: rule, rel: rel, src: src, fixed: fixed}) do
    "  • #{rel}  #{rule}\n" <> indent(first_diff_hunk(src, fixed), 6)
  end

  # The first changed run of lines, as a `- old / + new` hunk with a little
  # context, so the failure says exactly what the fix did to clean code.
  defp first_diff_hunk(src, fixed) do
    a = String.split(src, "\n")
    b = String.split(fixed, "\n")

    case List.myers_difference(a, b) do
      diff ->
        {prefix, rest} = Enum.split_while(diff, &match?({:eq, _}, &1))
        lead = prefix |> List.last() |> eq_tail(@context)

        changed =
          rest
          |> Enum.take_while(&(not match?({:eq, _}, &1)))
          |> Enum.flat_map(fn
            {:del, ls} -> Enum.map(ls, &"- #{&1}")
            {:ins, ls} -> Enum.map(ls, &"+ #{&1}")
            _ -> []
          end)

        (([Enum.map(lead, &"  #{&1}")] |> List.flatten()) ++ changed)
        |> Enum.join("\n")
    end
  end

  defp eq_tail(nil, _n), do: []
  defp eq_tail({:eq, ls}, n), do: Enum.take(ls, -n)

  defp indent(text, n) do
    pad = String.duplicate(" ", n)
    text |> String.split("\n") |> Enum.map_join("\n", &(pad <> &1))
  end
end
