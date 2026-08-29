defmodule Credence.FixByteScopeTest do
  @moduledoc """
  The byte-scope gate for the **Semantic** phase (docs/22 D2a).

  `self_corruption_test.exs` covers this class for Syntax by running a rule's
  `fix/1` over its own source. It cannot cover Semantic or Pattern at all —
  `fix/1` is the Syntax interface, and a Semantic rule needs a diagnostic. So the
  gate written for this class could physically reach 43 of 289 rules, and the one
  live instance it could not see was in `UndefinedFunction`: the catch-all owning
  every "undefined function …" message, reached by more rows than any other rule.

  This gate asks the same question through the interface Semantic actually has:
  compile each rule's own witness fixtures, find a diagnostic it claims, run
  `fix/2`, and check whether any **literal survived the edit with different
  content**.
  """
  use ExUnit.Case, async: false

  alias Credence.FixByteScope

  # ── The ledger ──────────────────────────────────────────────────────────
  #
  # `OutdentedHeredoc` exists to re-indent heredoc *bodies*, so editing masked
  # bytes is precisely its job and a hit here is correct behaviour. It is the
  # only rule in the phase that legitimately does this.
  #
  # The list may only shrink. A rule that stops offending must be removed from
  # it (the stale-entry test below), so the ledger cannot rot into permission.
  @ledger [Credence.Semantic.OutdentedHeredoc]

  describe "no Semantic rule rewrites the inside of a literal it leaves in place" do
    setup do
      %{entries: FixByteScope.scan()}
    end

    test "the ledger only grows by argument", %{entries: entries} do
      offenders = FixByteScope.offenders(entries)

      assert offenders -- @ledger == [],
             """
             A Semantic rule changed the contents of a string, charlist, sigil or
             comment that is still there after the fix. That is the byte-scope
             class (docs/22 T3.7, T3.10): the output still parses, still
             compiles, and still satisfies the rule's own tests, so nothing else
             will tell you.

             The repair is usually `Credence.SourceMask` — locate in the shadow,
             splice into the line, and mask the whole FILE, never a line alone.
             `Semantic.UndefinedFunction` is the worked example.

             Adding the rule to @ledger is NOT one of the options unless editing
             literal content is the rule's actual purpose.

             #{entries |> Enum.reject(&(&1.rule in @ledger)) |> Enum.map_join("\n", &FixByteScope.render/1)}
             """
    end

    test "and the ledger only shrinks — a paid-down entry must be removed", %{entries: entries} do
      stale = @ledger -- FixByteScope.offenders(entries)

      assert stale == [],
             """
             These rules are on @ledger but no longer edit literal content:

               #{Enum.map_join(stale, "\n  ", &inspect/1)}

             Remove them. A ledger that keeps entries after they are paid down
             stops being a record of debt and becomes permission for a
             regression.
             """
    end
  end

  # ── Controls ────────────────────────────────────────────────────────────
  #
  # These drive the machinery against fabricated rules rather than asserting
  # something about the real ones, because the real answer is "one rule, on
  # purpose" and will one day be "none". A gate whose vacuity check depends on
  # real debt existing stops working exactly when the debt is paid — the
  # T3.10a lesson, applied at construction instead of afterwards.

  describe "the machinery is provable without any real offender" do
    defp probe_scan(rules),
      do: FixByteScope.scan(rules, fn _rule -> [ByteScopeProbe.fixture()] end)

    test "a rule that rewrites inside a surviving string IS caught" do
      assert [%{rule: ByteScopeProbe.Corrupter}] =
               probe_scan([ByteScopeProbe.Corrupter])
    end

    test "a rule that rewrites only code is NOT caught" do
      assert probe_scan([ByteScopeProbe.Clean]) == []
    end

    test "a rule that REMOVES a literal is not caught — that is not this class" do
      assert probe_scan([ByteScopeProbe.Remover]) == []
    end

    test "a rule that INTRODUCES a literal is not caught either" do
      assert probe_scan([ByteScopeProbe.Introducer]) == []
    end

    test "a rule that declines is not caught" do
      assert probe_scan([ByteScopeProbe.Decliner]) == []
    end

    test "a rule whose fix/2 raises is a hit, not a skip" do
      assert probe_scan([ByteScopeProbe.Raiser]) == [
               %{
                 rule: ByteScopeProbe.Raiser,
                 fixture: ByteScopeProbe.fixture(),
                 line: 0,
                 was: "fix/2 completed",
                 now: "fix/2 raised RuntimeError: probe"
               }
             ]
    end
  end
end

# Fabricated rules for the controls. Deliberately NOT `use
# Credence.Semantic.Rule` — they are not rules and must never be discovered by
# `discover_rules/1`. The scanner only ever asks for `match?/1` and `fix/2`,
# which is what makes it drivable at all.
#
# Each declares its own fixture, because `PipelineWitness.candidates/1` harvests
# from test files that name the rule — and this file names all of them.
defmodule ByteScopeProbe do
  @fixture """
  defmodule ByteScopeProbeTarget do
    def f(l), do: {len(l), "the helper len(x) is not real"}
  end
  """

  def fixture, do: @fixture
end

defmodule ByteScopeProbe.Corrupter do
  def match?(%{message: m}), do: String.contains?(m, "undefined function len/1")
  def match?(_), do: false
  def priority, do: 500

  # The bug, in one line: replace every `len(` on the line, literals included.
  def fix(source, _d), do: String.replace(source, "len(", "length(")
end

defmodule ByteScopeProbe.Clean do
  def match?(%{message: m}), do: String.contains?(m, "undefined function len/1")
  def match?(_), do: false
  def priority, do: 500

  def fix(source, _d) do
    source
    |> Credence.SourceMask.lines()
    |> Enum.map_join("\n", fn {line, shadow} ->
      Credence.SourceMask.replace_code(line, shadow, "len(", "length(")
    end)
  end
end

defmodule ByteScopeProbe.Remover do
  def match?(%{message: m}), do: String.contains?(m, "undefined function len/1")
  def match?(_), do: false
  def priority, do: 500

  def fix(source, _d), do: String.replace(source, ~s|, "the helper len(x) is not real"|, "")
end

defmodule ByteScopeProbe.Introducer do
  def match?(%{message: m}), do: String.contains?(m, "undefined function len/1")
  def match?(_), do: false
  def priority, do: 500

  def fix(source, _d), do: String.replace(source, "len(l)", ~s|tagged("len", l)|)
end

defmodule ByteScopeProbe.Decliner do
  def match?(%{message: m}), do: String.contains?(m, "undefined function len/1")
  def match?(_), do: false
  def priority, do: 500

  def fix(source, _d), do: source
end

defmodule ByteScopeProbe.Raiser do
  def match?(%{message: m}), do: String.contains?(m, "undefined function len/1")
  def match?(_), do: false
  def priority, do: 500

  def fix(_source, _d), do: raise("probe")
end
