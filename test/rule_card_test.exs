defmodule Credence.RuleCardTest do
  @moduledoc """
  Rule Standard requirement 6 — the rule card (docs/12 **C15**).

  Two things are gated here, for two different reasons.

  ## The intent line — a dedup signal, not documentation

  Every rule's moduledoc must open with **one sentence** saying what the rule
  does. That sentence is what the harness's classifier reads to decide whether a
  proposed rule already exists (H8's verdict memory and the rule index it is
  built from). A list of rule *names* teaches a generating model nothing — the
  next proposal arrives under a different name — so the one-line mechanism
  statement is the entire dedup signal, and 25 of the 143 rejected rules in the
  evolution were re-inventions of live ones.

  Measured before gating: **274 of 289 rules already comply**, so this is a
  ratchet from the day it lands rather than a wall. The 14 that do not are
  ledgered.

  ## `## Bad` / `## Good` on Syntax rules — test infrastructure

  Gated for **Syntax only**, and not as a documentation nicety. The
  self-corruption oracle works by running a Syntax rule's `fix/1` over its own
  source file, and what makes that file adversarial is precisely that the
  Rule Standard requires the moduledoc to contain the exact byte sequences the
  rule rewrites, inside a heredoc, beside prose naming the operator in English.
  Remove the `## Bad` block and the oracle still runs — over a file with nothing
  in it to corrupt. It goes green by having nothing to find, which is the worst
  way for a gate to pass.

  So on Syntax these examples are load-bearing, and compliance is already 40 of
  43. On Pattern (120/157) and Semantic (6/89) the same block is documentation
  and a second dedup signal; valuable, not load-bearing, and an 83-entry
  Semantic ledger would be a wall rather than a ratchet. Tracked in `STATUS.md`
  D5 instead of gated here.
  """
  use ExUnit.Case, async: true

  @intent_ledger [
    Credence.Pattern.NoCaseDestructureInPipe,
    Credence.Pattern.NoCaseTupleGuardDispatch,
    Credence.Pattern.NoCondTwoClauses,
    Credence.Pattern.NoLengthBasedIndexing,
    Credence.Pattern.NoLiteralListTypespec,
    Credence.Pattern.NoReduceForMapBuilding,
    Credence.Pattern.NoReduceWhileWithoutHalt,
    Credence.Pattern.NoSortThenAt,
    Credence.Pattern.NoStringLengthForCharCheck,
    Credence.Pattern.PreferEnumReverseTwo,
    Credence.Pattern.PreferExplicitBinaryArithmetic,
    Credence.Pattern.PreferGuardOverIf,
    Credence.Pattern.UnnecessaryGraphemeChunking,
    Credence.Semantic.UndefinedStringAlphanumeric
  ]

  @bad_good_ledger [
    Credence.Syntax.CloseUnclosedFnDelimiter,
    Credence.Syntax.FixAssignmentDotSyntax,
    Credence.Syntax.FixStaleAccessModifier
  ]

  defp all_rules do
    Credence.Pattern.default_rules() ++
      Credence.Semantic.default_rules() ++ Credence.Syntax.default_rules()
  end

  defp moduledoc(rule) do
    case Code.fetch_docs(rule) do
      {:docs_v1, _, _, _, %{"en" => doc}, _, _} -> doc
      _ -> nil
    end
  end

  defp intent_line(doc) do
    doc |> String.split("\n\n") |> Enum.find("", &(String.trim(&1) != "")) |> String.trim()
  end

  # ". " followed by a capital is the sentence boundary that matters here. It
  # deliberately does not split on "e.g." or "Enum.map/2" — a period inside a
  # token has no following space, and a period before a lowercase word is not a
  # new sentence.
  defp sentences(paragraph), do: String.split(paragraph, ~r/\.\s+[A-Z]/)

  describe "every rule has a moduledoc" do
    test "no rule ships without one" do
      missing = Enum.filter(all_rules(), &is_nil(moduledoc(&1)))

      assert missing == [],
             "these rules have no @moduledoc:\n  #{Enum.map_join(missing, "\n  ", &inspect/1)}"
    end
  end

  describe "the intent line" do
    test "the moduledoc opens with prose, never a heading or an example" do
      bad =
        Enum.filter(all_rules(), fn rule ->
          line = rule |> moduledoc() |> intent_line()
          String.starts_with?(line, "#") or String.starts_with?(line, "    ") or line == ""
        end)

      assert bad == [],
             """
             A rule card opens with one sentence saying what the rule does — not
             a heading, not a code block. That sentence is the dedup signal the
             classifier reads.

               #{Enum.map_join(bad, "\n  ", &inspect/1)}
             """
    end

    test "and it is a single sentence — the ledger only grows by argument" do
      offenders =
        Enum.filter(all_rules(), fn rule ->
          rule |> moduledoc() |> intent_line() |> sentences() |> length() > 1
        end)

      assert offenders -- @intent_ledger == [],
             """
             The first paragraph of these rules' moduledocs holds more than one
             sentence, so there is no single statement of intent for the
             classifier's dedup index to read (docs/12 C15, Rule Standard
             requirement 6):

               #{Enum.map_join(offenders -- @intent_ledger, "\n  ", &inspect/1)}

             Split it: one sentence naming the mechanism, blank line, then as
             much prose as the rule deserves.
             """
    end

    test "and the ledger only shrinks — a paid-down entry must be removed" do
      offenders =
        Enum.filter(all_rules(), fn rule ->
          rule |> moduledoc() |> intent_line() |> sentences() |> length() > 1
        end)

      stale = @intent_ledger -- offenders

      assert stale == [],
             """
             These rules are on @intent_ledger but now have a single-sentence
             intent line. Remove them — a ledger that keeps paid-down entries
             becomes permission for a regression:

               #{Enum.map_join(stale, "\n  ", &inspect/1)}
             """
    end
  end

  describe "Syntax rules carry the examples the self-corruption oracle needs" do
    defp syntax_without_examples do
      Enum.filter(Credence.Syntax.default_rules(), fn rule ->
        doc = moduledoc(rule)
        not (String.contains?(doc, "## Bad") and String.contains?(doc, "## Good"))
      end)
    end

    test "the ledger only grows by argument" do
      assert syntax_without_examples() -- @bad_good_ledger == [],
             """
             These Syntax rules have no `## Bad` / `## Good` block. For a Syntax
             rule that is not a documentation gap — `self_corruption_test.exs`
             runs the rule's own `fix/1` over its own source file, and the Bad
             example IS the adversarial input. Without it the oracle passes by
             having nothing to find.

               #{Enum.map_join(syntax_without_examples() -- @bad_good_ledger, "\n  ", &inspect/1)}
             """
    end

    test "and the ledger only shrinks" do
      stale = @bad_good_ledger -- syntax_without_examples()

      assert stale == [],
             "paid down, remove from @bad_good_ledger:\n  #{Enum.map_join(stale, "\n  ", &inspect/1)}"
    end
  end

  describe "the sentence splitter does not fire on ordinary rule prose" do
    # Controls. The splitter decides the whole intent gate, so its false
    # positives would be indistinguishable from real offences.
    test "a module or function reference is not a sentence boundary" do
      assert length(sentences("Rewrites `Enum.map/2` into a comprehension.")) == 1
      assert length(sentences("Detects `String.length(s) == 1` in a guard.")) == 1
    end

    test "an abbreviation is not a sentence boundary" do
      assert length(sentences("Flags a call to e.g. `Map.get/2` with a default.")) == 1
    end

    test "but two real sentences are" do
      assert length(sentences("Does a thing. Then it does another thing.")) == 2
    end
  end
end
