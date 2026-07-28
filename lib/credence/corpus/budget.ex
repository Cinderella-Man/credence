defmodule Credence.Corpus.Budget do
  @moduledoc """
  The **per-rule accepted-findings budget** — the published view of
  `test/corpus/accepted_findings.txt`, and the arithmetic behind the gate that
  keeps it from growing quietly (docs/12 C13, docs/19 §2 row C, Rule Standard
  item 8).

  ## What was already enforced, and what was not

  `test/corpus/over_firing_test.exs` asserts the *live* findings equal the
  committed snapshot, per package, exactly. That is already a ratchet against
  **code** changes: no rule can start firing on the corpus without a red test.
  What it does not gate is the **accept**: the failure message says "re-pin with
  `mix credence.corpus --update-snapshot`", the re-pin is one command, and the
  resulting diff is N raw `<path>:<line>  <rule>` lines with no per-rule
  aggregate anywhere. That is how the snapshot reached 6,366 accepted findings
  across 87 rules with 74% of the mass in 15 rules and 20% in one
  (`prefer_heredoc_for_multi_line_doc`, 1,298) without anyone deciding to.

  This module supplies the missing half:

    * `counts/1` — the per-rule count of the snapshot, **with multiplicity**: a
      snapshot line carrying `(xN)` counts N, because a rule that fires three
      times on one source line is three suppressed fix sites. (Counting *lines*
      would let a rule grow from 100 to 300 findings without moving its budget,
      since `(x1)`→`(x3)` is a line edit, not a new line.)
    * `render/2` / `parse/1` — the committed publication of those counts,
      `test/corpus/accepted_findings_budget.txt`, so every accept shows up in
      review as `-  504  prefer_map_new` / `+  904  prefer_map_new` rather than
      400 opaque path lines.
    * `violations/3` — the gate itself, as data. `test/corpus/findings_budget_test.exs`
      holds the frozen policy (the cap and the grandfather ledger) and asserts
      this returns `[]`.

  ## The policy this module computes against

  Deliberately *not* stored here — it is frozen in the gate test, the same way
  `@verified_dsl_safe` is frozen in `Credence.Pattern.DslSafetyClassificationTest`.
  A library module should not carry the project's own corpus policy, and keeping
  the numbers in the test means raising one is a visible edit to a gate rather
  than to a helper.

  Four violation classes, in the order `violations/3` returns them:

    * `{:out_of_sync, rule, published, actual}` — the budget file disagrees with
      the snapshot. Exact equality, no slack in either direction: slack above the
      real count is refill room, and slack below is a file nobody regenerated.
    * `{:over_cap, rule, count, cap}` — a rule **not** on the grandfather ledger
      exceeding the cap. This is the gate with teeth: a new rule cannot land
      style-heavy.
    * `{:over_grandfather, rule, count, ceiling}` — a grandfathered rule above its
      adoption-day ceiling. Those 15 ceilings are high-water marks; they may only
      fall.
    * `{:graduated, rule, count, cap}` — a grandfathered rule that has fallen to
      the cap or below and must now **leave** the ledger. This is what makes the
      ledger shrink and makes a paydown permanent: once a rule is off the ledger
      it can never exceed the cap again without a deliberate re-grandfathering.

  ## Why the cap is 100

  C13 proposes 100, and the measured distribution puts its own knee there: the
  15th-largest rule has 122 accepted findings and the 16th has 99. A cap of 100
  therefore sits in a real gap in the data, grandfathers exactly the 15 rules
  that hold 74% of the debt, and leaves the other 72 firing rules (and the 68
  Pattern rules that fire zero times) already compliant with no slack to spare.
  """

  alias Credence.Corpus.Findings

  @budget_relpath "test/corpus/accepted_findings_budget.txt"

  # A budget row: an integer count, two-or-more spaces, the snake rule name.
  @row_regex ~r/^\s*(?<count>\d+)\s+(?<rule>[a-z][a-z0-9_]*)\s*$/

  # Per-rule cap for any rule not on the grandfather ledger. Lives here (rather
  # than in the gate test alongside the ledger) only so the `mix credence.corpus
  # --budget` report and the gate cannot disagree about the number.
  @default_cap 100

  @type rule :: String.t()
  @type counts :: %{rule() => pos_integer()}
  @type ledger :: %{rule() => pos_integer()}
  @type violation ::
          {:out_of_sync, rule(), non_neg_integer(), non_neg_integer()}
          | {:over_cap, rule(), pos_integer(), pos_integer()}
          | {:over_grandfather, rule(), pos_integer(), pos_integer()}
          | {:graduated, rule(), non_neg_integer(), pos_integer()}

  @doc "The per-rule cap applied to every rule not on the grandfather ledger."
  @spec default_cap() :: pos_integer()
  def default_cap, do: @default_cap

  @doc "Repo-relative path of the committed budget file."
  @spec budget_relpath() :: String.t()
  def budget_relpath, do: @budget_relpath

  @doc "Absolute path to the committed budget file."
  @spec budget_path() :: String.t()
  def budget_path, do: Path.join(File.cwd!(), @budget_relpath)

  @doc """
  Per-rule accepted-finding counts for a list of snapshot identity lines,
  **weighted by the `(xN)` multiplicity**. Lines that are not identities
  (comments, blanks, anything `Credence.Corpus.Findings.rule_of/1` does not
  recognise) are ignored, exactly as the over-firing test ignores them.

      iex> Credence.Corpus.Budget.counts(["a.ex:1  r", "a.ex:2  r  (x3)", "# c"])
      %{"r" => 4}
  """
  @spec counts([String.t()]) :: counts()
  def counts(lines) when is_list(lines) do
    Enum.reduce(lines, %{}, fn line, acc ->
      case Findings.rule_of(line) do
        nil ->
          acc

        rule ->
          n = Findings.count_of(line)
          Map.update(acc, rule, n, &(&1 + n))
      end
    end)
  end

  @doc "Total accepted findings across every rule in `counts`."
  @spec total(counts()) :: non_neg_integer()
  def total(counts), do: counts |> Map.values() |> Enum.sum()

  @doc """
  The per-rule counts published in the committed budget file, or `%{}` when the
  file does not exist yet (which the gate reports as every rule being
  out-of-sync, rather than passing vacuously).
  """
  @spec published() :: counts()
  def published do
    case File.read(budget_path()) do
      {:ok, body} -> parse(body)
      {:error, _} -> %{}
    end
  end

  @doc """
  Parse a budget file body into `%{rule => count}`.

  Blank lines and `#` comments are skipped; **anything else that is not a
  well-formed row raises**, as does a repeated rule. The file is machine-written
  by `mix credence.corpus --update-budget`, so a line this cannot read is a hand
  edit or a botched merge conflict — and silently dropping it would quietly
  shrink the published total, which is the one direction that must never be
  quiet.
  """
  @spec parse(String.t()) :: counts()
  def parse(body) when is_binary(body) do
    body
    |> String.split("\n")
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.reject(&(String.trim(&1) == "" or String.starts_with?(String.trim(&1), "#")))
    |> Enum.reduce(%{}, fn line, acc ->
      case Regex.named_captures(@row_regex, line) do
        %{"count" => count, "rule" => rule} ->
          if Map.has_key?(acc, rule) do
            raise ArgumentError,
                  "#{@budget_relpath}: rule #{inspect(rule)} appears twice. " <>
                    "Regenerate with `mix credence.corpus --update-budget`."
          end

          Map.put(acc, rule, String.to_integer(count))

        nil ->
          raise ArgumentError,
                "#{@budget_relpath}: cannot parse row #{inspect(line)} " <>
                  "(expected \"<count>  <rule>\"). " <>
                  "Regenerate with `mix credence.corpus --update-budget`."
      end
    end)
  end

  @doc """
  Render `counts` as the committed budget file body — the inverse of `parse/1`,
  sorted by count descending then rule name, so the diff of an accept is the
  per-rule delta and the paydown ranking is the file's own order.
  """
  @spec render(counts(), keyword()) :: String.t()
  def render(counts, opts \\ []) do
    cap = Keyword.get(opts, :cap, @default_cap)
    rows = rank(counts)
    {over, under} = Enum.split_with(rows, fn {_rule, count} -> count > cap end)
    over_total = over |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    grand_total = total(counts)

    header(%{
      cap: cap,
      rules: length(rows),
      total: grand_total,
      over: length(over),
      under: length(under),
      over_total: over_total,
      share: percent(over_total, grand_total),
      top: List.first(rows)
    }) <> Enum.map_join(rows, "\n", &row/1) <> "\n"
  end

  @doc """
  Every way the committed state can be out of policy, as data — `[]` means the
  budget holds. See the moduledoc for the four classes.

  `opts` carries the frozen policy: `:grandfathered` (required) is
  `%{rule => adoption ceiling}`, `:cap` defaults to `default_cap/0`.
  """
  @spec violations(counts(), counts(), keyword()) :: [violation()]
  def violations(counts, published, opts) do
    cap = Keyword.get(opts, :cap, @default_cap)
    ledger = Keyword.fetch!(opts, :grandfathered)

    out_of_sync(counts, published) ++
      over_cap(counts, ledger, cap) ++
      over_grandfather(counts, ledger) ++
      graduated(counts, ledger, cap)
  end

  @doc """
  Render `violations/3` output as an assertion message: what is wrong, by how
  much, and the one action that resolves it.
  """
  @spec explain([violation()]) :: String.t()
  def explain([]), do: "the accepted-findings budget holds"

  def explain(violations) do
    "\n" <> Enum.map_join(violations, "\n\n", &describe/1) <> "\n"
  end

  @doc """
  The per-rule delta between two count maps, as `[{rule, from, to}]` sorted by
  the size of the change. Reported by `mix credence.corpus --update-snapshot`
  so the accept states its own cost at the moment it is made.
  """
  @spec deltas(counts(), counts()) :: [{rule(), non_neg_integer(), non_neg_integer()}]
  def deltas(from, to) do
    from
    |> Map.keys()
    |> Enum.concat(Map.keys(to))
    |> Enum.uniq()
    |> Enum.map(fn rule -> {rule, Map.get(from, rule, 0), Map.get(to, rule, 0)} end)
    |> Enum.reject(fn {_rule, a, b} -> a == b end)
    |> Enum.sort_by(fn {rule, a, b} -> {-abs(b - a), rule} end)
  end

  @doc """
  Rules ordered the way the budget file and the report order them: most accepted
  findings first, ties broken by name.
  """
  @spec rank(counts()) :: [{rule(), pos_integer()}]
  def rank(counts), do: Enum.sort_by(counts, fn {rule, count} -> {-count, rule} end)

  # --- violation classes -----------------------------------------------------

  defp out_of_sync(counts, published) do
    counts
    |> Map.keys()
    |> Enum.concat(Map.keys(published))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(fn rule ->
      actual = Map.get(counts, rule, 0)
      pub = Map.get(published, rule, 0)
      if actual == pub, do: [], else: [{:out_of_sync, rule, pub, actual}]
    end)
  end

  defp over_cap(counts, ledger, cap) do
    counts
    |> rank()
    |> Enum.flat_map(fn {rule, count} ->
      if count > cap and not Map.has_key?(ledger, rule),
        do: [{:over_cap, rule, count, cap}],
        else: []
    end)
  end

  defp over_grandfather(counts, ledger) do
    ledger
    |> Enum.sort()
    |> Enum.flat_map(fn {rule, ceiling} ->
      count = Map.get(counts, rule, 0)
      if count > ceiling, do: [{:over_grandfather, rule, count, ceiling}], else: []
    end)
  end

  defp graduated(counts, ledger, cap) do
    ledger
    |> Enum.sort()
    |> Enum.flat_map(fn {rule, _ceiling} ->
      count = Map.get(counts, rule, 0)
      if count <= cap, do: [{:graduated, rule, count, cap}], else: []
    end)
  end

  # --- rendering -------------------------------------------------------------

  defp describe({:out_of_sync, rule, published, actual}) do
    """
      #{rule}: the budget file says #{published}, the snapshot holds #{actual}.
        The published budget is a view of test/corpus/accepted_findings.txt and
        must equal it exactly. Regenerate it (no corpus fetch needed — it is
        derived from the committed snapshot):
            mix credence.corpus --update-budget
        Then read the diff: it is the per-rule cost of whatever was accepted.\
    """
  end

  defp describe({:over_cap, rule, count, cap}) do
    """
      #{rule}: #{count} accepted corpus findings, cap is #{cap}.
        A rule that fires #{count} times on well-reviewed production code is a
        style rule by the harness's own NO_ACTION class-1 definition, and every
        one of those findings is a suppressed fix site plus a re-pin burden on
        every package bump (docs/12 C13). Narrow the rule, demote it behind an
        opt-in assumption, or retire it. Grandfathering it instead means adding
        it to @grandfathered in test/corpus/findings_budget_test.exs with the
        number — which is a deliberate, reviewable act, and is the point.\
    """
  end

  defp describe({:over_grandfather, rule, count, ceiling}) do
    """
      #{rule}: #{count} accepted corpus findings, grandfathered ceiling is #{ceiling} (+#{count - ceiling}).
        Grandfathered ceilings are adoption-day high-water marks: they ratchet
        DOWN only. Either narrow the rule back under #{ceiling}, or raise the
        number in @grandfathered (test/corpus/findings_budget_test.exs) on
        purpose and say why in the commit.\
    """
  end

  defp describe({:graduated, rule, count, cap}) do
    """
      #{rule}: down to #{count} accepted corpus findings — at or under the cap of #{cap}.
        Remove it from @grandfathered in test/corpus/findings_budget_test.exs.
        That is what makes the ledger shrink, and it makes the paydown permanent:
        off the ledger, the rule can never exceed the cap again without a
        deliberate re-grandfathering.\
    """
  end

  defp row({rule, count}), do: "#{String.pad_leading(Integer.to_string(count), 5)}  #{rule}"

  defp percent(_part, 0), do: 0
  defp percent(part, whole), do: round(part * 100 / whole)

  defp header(%{top: nil} = info) do
    preamble(info) <> "# EMPTY — no rule fires on the corpus.\n\n"
  end

  defp header(%{top: {top_rule, top_count}} = info) do
    preamble(info) <>
      """
      # TOTAL #{info.total} accepted findings across #{info.rules} rules.
      #      #{info.over} over the cap of #{info.cap} (grandfathered; they hold #{info.over_total} = #{info.share}% of the debt)
      #      #{info.under} at or under the cap
      #
      # Paydown ranking is this file's own order. Top target (docs/16, C13(b)):
      # #{top_rule}, #{top_count} = #{percent(top_count, info.total)}% of the whole budget.

      """
  end

  defp preamble(_info) do
    """
    # Accepted corpus findings — PER-RULE BUDGET (docs/12 C13, docs/19 §2 row C).
    #
    # The published per-rule view of test/corpus/accepted_findings.txt:
    #
    #     <accepted findings>  <rule>
    #
    # counted WITH multiplicity — a snapshot line carrying `(xN)` counts N,
    # because a rule firing three times on one source line is three suppressed
    # fix sites.
    #
    # DO NOT hand-edit. Regenerate from the committed snapshot (no corpus fetch
    # needed) after re-pinning:
    #
    #     mix credence.corpus --update-budget
    #
    # test/corpus/findings_budget_test.exs gates this file, WITHOUT needing the
    # corpus, so it runs under `mix test --exclude corpus` too:
    #
    #   * it must equal the snapshot's per-rule counts exactly — no slack, because
    #     slack above the real count is refill room;
    #   * a rule NOT on the frozen grandfather ledger may not exceed the cap;
    #   * a grandfathered rule may not exceed its adoption-day ceiling, and MUST
    #     leave the ledger once it falls to the cap or below.
    #
    # The cap and the ledger are frozen in that test. Changing either is a
    # deliberate, reviewable edit — which is the whole mechanism.
    #
    """
  end
end
