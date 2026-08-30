defmodule Credence.FixtureScopeParityTest do
  use ExUnit.Case, async: true

  alias Credence.FixOrDrop
  alias Credence.RuleHelpers

  @moduledoc """
  Scope parity over each rule's OWN fixtures.

  `test/corpus/scope_parity_test.exs` states the invariant and enforces it over the
  ~20,000-file corpus: if a rule's check leaves a file clean, its fix must not
  change it — a fix that rewrites check-clean code selects something the check does
  not, and the cure is to have both share one scope predicate.

  ## Why a second layer, over fixtures

  The corpus layer only sees shapes the corpus contains, and a rule's own defects
  usually are not among them. Two examples from 2026-08-17, both of which this
  layer catches and the corpus layer could not:

    * `no_negative_step_in_string_slice` shipped with `check/2` matching only the
      two-argument `String.slice(str, range)` while `fix_patches/2` carried an
      explicit branch for the piped one-argument form. The corpus holds three
      findings for that rule, all direct calls, so the piped form was never
      probed.
    * `no_keyword_get_integer_key` fixed shapes its check never reported, then —
      once the fix was widened — claimed a sibling rule's defect. It has **zero**
      corpus findings, so the corpus layer had nothing at all to say about it.

  A rule's fixtures are written to cover its shapes, which is exactly the
  population this invariant wants.

  ## What it does NOT see, measured

  `FixOrDrop.fixtures/1` collects string LITERALS sitting next to a verb call
  (`check(...)`, `fix(...)`, `flagged?(...)`). A fixture assembled by interpolation
  — `for src <- [...] do wrapped = "defmodule M do ... \#{src} ... end"` — is
  invisible to it, because there is no literal to collect. Verified on
  `no_negative_step_in_string_slice`: 16 fixtures collected, and the piped
  `s |> String.slice(2..-1)` case written in exactly that shape is not among them,
  so re-introducing the piped defect leaves this gate green.

  That is a real limit and not a reason to drop the layer — re-introducing the
  OTHER defect from the same day, a narrowing applied to `check/2` and not to
  `fix_patches/2`, turns it red immediately. But it does mean a rule whose only
  coverage of a shape is an interpolated fixture is not covered here.

  ## Direction

  One-directional, deliberately: **check-clean must imply fix-unchanged.** The
  converse (flagged must imply changed) belongs to `fix_or_drop_test.exs`, which
  owns it and knows about the legitimate reasons a fix declines — a rejected patch,
  a revert on a worse compile, a rule that narrows on purpose. Asserting it here
  too would duplicate that judgement and disagree with it.
  """

  @rules Credence.Pattern.default_rules()

  # A fixture that does not parse cannot be handed to `check/2`, and a rule that
  # only ever runs on parsing source is not the subject of this invariant.
  defp parseable(fixtures) do
    Enum.filter(fixtures, &match?({:ok, _}, Sourceror.parse_string(&1)))
  end

  test "no rule's fix changes a fixture its own check leaves clean" do
    violations =
      for rule <- @rules,
          fixture <- rule |> FixOrDrop.fixtures() |> parseable(),
          clean?(rule, fixture),
          changed = RuleHelpers.apply_rule_fix(rule, fixture),
          changed != fixture do
        {rule, fixture, changed}
      end

    assert violations == [], format(violations)
  end

  # The floor. If the fixture index breaks, every rule silently has "no fixtures"
  # and this passes by having nothing to check — the T3.10a failure this project
  # has already been bitten by once.
  test "the fixture population is real" do
    counted =
      for rule <- @rules, reduce: 0 do
        acc -> acc + length(FixOrDrop.fixtures(rule))
      end

    assert counted > 500,
           "only #{counted} fixtures collected across #{length(@rules)} rules; " <>
             "the extractor has regressed and this gate is vacuous"
  end

  # Fixtures are multi-line; a one-line excerpt hides which line moved, which is
  # the only thing a reader needs.
  defp indent(source, prefix) do
    source
    |> String.trim_trailing()
    |> String.split("\n")
    |> Enum.map_join("\n        ", &(prefix <> &1))
  end

  defp clean?(rule, source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} -> rule.check(ast, source: source) == []
      _ -> false
    end
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  defp format(violations) do
    body =
      violations
      |> Enum.map_join("\n\n", fn {rule, before, after_} ->
        """
          #{inspect(rule)} — check says clean, fix rewrote it:

        #{indent(before, "  before| ")}
        #{indent(after_, "  after | ")}
        """
      end)

    """
    A fix changed a fixture its own check reports nothing on.

    That means the fix selects something the check does not, and a user running
    `analyze` then `fix` sees code change with no finding to explain it. The cure
    is one scope predicate shared by both callbacks, not two that agree today.

    #{body}
    """
  end
end
