defmodule Credence.FixByteScope do
  @moduledoc """
  The byte-scope oracle for the **Semantic** phase: *a fix may only change bytes
  that were code*.

  ## Why this exists

  `Credence.SelfCorruption` catches the same class by running a rule's `fix/1`
  over its own source file — and it can only ever cover **Syntax**, because
  Syntax is the one phase whose fix takes a bare string. A Semantic rule needs a
  diagnostic to drive `fix/2`, so the gate built precisely for this class was
  structurally blind to two thirds of the rule set.

  That was not hypothetical. `Semantic.UndefinedFunction` — the catch-all owning
  every "undefined function …" message, and the most-reached rule in the tree —
  shipped rewriting a same-named call **inside a string literal** and **inside a
  trailing comment**, because its per-line helpers ran a plain
  `String.replace`/`Regex.replace` over the raw line. Nothing could see it: the
  output parses, compiles, and satisfies every assertion in the rule's own tests.

  ## The check

  For each rule, for each of its own witness fixtures: compile the fixture,
  find a diagnostic the rule claims, run `fix/2`, and compare. Every byte the
  fix **changed** is checked against `Credence.SourceMask.mask/1` of the
  *original*. A changed byte that was masked — a string body, a charlist, a
  sigil, a comment — is a hit.

  The comparison is per line and only for lines that survive as lines, via
  `List.myers_difference/2`. Whole-line insertions and deletions are ignored on
  purpose: a rule that deletes a `@doc` line is doing its job, and that is a
  different question from whether a rewrite reached into a literal.

  ## What a hit means

  Exactly what the Syntax oracle's hit means, and no more: **the rule edited
  bytes that are not code.** It does not say the repair is `SourceMask`, and it
  does not say the rule is wrong — `OutdentedHeredoc` exists to edit heredoc
  bodies, and for it a hit is correct behaviour. Those are ledgered.
  """

  alias Credence.RuleHelpers
  alias Credence.SourceMask

  @self_reported "credence_check.ex"

  @doc """
  `[%{rule:, fixture:, line:, was:, now:}]` — one entry per line where `rule`'s
  fix changed a byte that the original had masked as non-code.

  Takes its rule list as an argument so the controls can drive it against
  fabricated rules: a gate whose vacuity depends on real debt existing stops
  working the moment the debt is paid (the T3.10a lesson).
  """
  @spec scan([module()], (module() -> [String.t()])) :: [map()]
  def scan(rules \\ Credence.Semantic.default_rules(), candidates \\ &default_candidates/1) do
    Enum.flat_map(rules, &scan_rule(&1, candidates))
  end

  @doc "Where fixtures come from in the live gate: the witness index."
  def default_candidates(rule), do: Credence.PipelineWitness.candidates(rule)

  defp scan_rule(rule, candidates) do
    rule
    |> candidates.()
    |> Enum.flat_map(fn fixture ->
      rule
      |> claimed_diagnostics(fixture)
      |> Enum.flat_map(&non_code_edits(rule, fixture, &1))
    end)
    |> Enum.uniq_by(&{&1.line, &1.was, &1.now})
  end

  defp claimed_diagnostics(rule, source) do
    source
    |> diagnostics_of()
    |> Enum.reject(&String.starts_with?(&1.message, @self_reported))
    |> Enum.filter(&safe_match?(rule, &1))
  end

  defp diagnostics_of(source) do
    case RuleHelpers.compile_and_capture(source) do
      {:ok, diagnostics} -> Enum.filter(diagnostics, &(&1.severity in [:warning, :error]))
      {:error, diagnostics} -> Enum.filter(diagnostics, &(&1.severity == :error))
    end
  rescue
    _ -> []
  catch
    _, _ -> []
  end

  # A rule that raises on an unfamiliar diagnostic must not take the scan down
  # with it — and must not be scored as declining either, so it is skipped.
  defp safe_match?(rule, diagnostic) do
    rule.match?(diagnostic)
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  defp non_code_edits(rule, source, diagnostic) do
    case safe_fix(rule, source, diagnostic) do
      {:ok, ^source} ->
        []

      {:ok, nil} ->
        []

      {:ok, fixed} ->
        was_shadows = shadow_lines(source)
        now_shadows = shadow_lines(fixed)

        source
        |> changed_lines(fixed)
        |> Enum.flat_map(&flag(rule, source, &1, was_shadows, now_shadows))

      {:error, reason} ->
        [
          %{
            rule: rule,
            fixture: source,
            line: 0,
            was: "fix/2 completed",
            now: reason
          }
        ]
    end
  end

  defp shadow_lines(source), do: source |> SourceMask.lines() |> Enum.map(&elem(&1, 1))

  defp safe_fix(rule, source, diagnostic) do
    {:ok, rule.fix(source, diagnostic)}
  rescue
    error -> {:error, "fix/2 raised #{inspect(error.__struct__)}: #{Exception.message(error)}"}
  catch
    kind, reason -> {:error, "fix/2 #{kind}: #{inspect(reason)}"}
  end

  # Pair up lines that were rewritten in place. `myers_difference` reports a
  # rewrite as a `:del` run immediately followed by an `:ins` run; only where
  # the two runs are the same length is a positional pairing meaningful — that
  # is the `log_diff/3` lesson (index-pairing whole files fabricates diffs).
  defp changed_lines(source, fixed) do
    orig = String.split(source, "\n")
    new = String.split(fixed, "\n")

    orig
    |> List.myers_difference(new)
    |> pair_runs()
  end

  defp pair_runs(diff), do: pair_runs(diff, 1, 1, [])

  defp pair_runs([], _a, _b, acc), do: Enum.reverse(acc)

  defp pair_runs([{:eq, lines} | rest], a, b, acc),
    do: pair_runs(rest, a + length(lines), b + length(lines), acc)

  defp pair_runs([{:del, dels}, {:ins, ins} | rest], a, b, acc)
       when length(dels) == length(ins) do
    paired =
      [dels, ins, 0..(length(dels) - 1)//1]
      |> Enum.zip()
      |> Enum.reject(fn {d, i, _} -> d == i end)
      |> Enum.map(fn {d, i, k} -> %{line: a + k, new_line: b + k, was: d, now: i} end)

    pair_runs(rest, a + length(dels), b + length(ins), Enum.reverse(paired) ++ acc)
  end

  defp pair_runs([{:del, dels}, {:ins, ins} | rest], a, b, acc) do
    paired = pair_similar_lines(dels, ins, a, b)
    pair_runs(rest, a + length(dels), b + length(ins), Enum.reverse(paired) ++ acc)
  end

  defp pair_runs([{:del, dels} | rest], a, b, acc),
    do: pair_runs(rest, a + length(dels), b, acc)

  defp pair_runs([{:ins, ins} | rest], a, b, acc), do: pair_runs(rest, a, b + length(ins), acc)

  # An in-place rewrite can share a Myers hunk with an adjacent line insertion
  # or deletion. Pair only strongly similar lines in those unequal runs; the
  # leftovers remain genuine whole-line changes and are deliberately ignored.
  defp pair_similar_lines(dels, ins, a, b) do
    candidates =
      for {del, di} <- Enum.with_index(dels),
          {inserted, ii} <- Enum.with_index(ins),
          score = String.jaro_distance(del, inserted),
          score >= 0.8,
          do: {score, di, ii, del, inserted}

    candidates
    |> Enum.sort_by(fn {score, _, _, _, _} -> score end, :desc)
    |> Enum.reduce({MapSet.new(), MapSet.new(), []}, fn
      {_score, di, ii, del, inserted}, {used_dels, used_ins, pairs} ->
        if MapSet.member?(used_dels, di) or MapSet.member?(used_ins, ii) do
          {used_dels, used_ins, pairs}
        else
          pair = %{line: a + di, new_line: b + ii, was: del, now: inserted}
          {MapSet.put(used_dels, di), MapSet.put(used_ins, ii), [pair | pairs]}
        end
    end)
    |> elem(2)
    |> Enum.sort_by(& &1.line)
  end

  # Three things a fix can do to the literals on a line, and only one is the bug:
  #
  #   * REMOVE one — `def f(x \\ "world")` losing its default. Correct.
  #   * INTRODUCE one — `String.alphanumeric?/1` becoming a `~r/.../` match.
  #     Correct, and the repair would be impossible otherwise.
  #   * CHANGE one — a literal disappears and a near-copy takes its place. That
  #     is what rewriting inside a string looks like from outside, and there is
  #     no other way for a fix to produce it.
  #
  # So the flag needs BOTH directions to be non-empty. Requiring only that every
  # output body was present in the input (the first version of this check) reads
  # every legitimate introduction as a hit — measured: it accused
  # `UndefinedStringAlphanumeric` of corruption for adding the regex its repair
  # is made of.
  defp flag(rule, source, %{line: a, new_line: b, was: was, now: now}, was_shadows, now_shadows) do
    before_bodies = literal_bodies(was, Enum.at(was_shadows, a - 1))
    after_bodies = literal_bodies(now, Enum.at(now_shadows, b - 1))

    vanished = before_bodies -- after_bodies
    appeared = after_bodies -- before_bodies

    if vanished != [] and appeared != [] do
      [%{rule: rule, fixture: source, line: a, was: was, now: now}]
    else
      []
    end
  end

  # The byte runs the mask blanked, taken from the real line — i.e. the contents
  # of every string, charlist, sigil and comment on it. `nil` shadow means the
  # line index fell outside the file, which can only happen on a malformed diff;
  # returning `[]` makes that a miss rather than a false accusation.
  defp literal_bodies(_line, nil), do: []

  defp literal_bodies(line, shadow) do
    shadow
    |> masked_runs(0, nil, [])
    |> Enum.map(fn {start, len} -> safe_slice(line, start, len) end)
    |> Enum.reject(&(String.trim(&1) == ""))
  end

  defp masked_runs(shadow, i, open, acc) when i < byte_size(shadow) do
    masked? = :binary.at(shadow, i) == 0x01

    cond do
      masked? and is_nil(open) -> masked_runs(shadow, i + 1, i, acc)
      masked? -> masked_runs(shadow, i + 1, open, acc)
      is_nil(open) -> masked_runs(shadow, i + 1, nil, acc)
      true -> masked_runs(shadow, i + 1, nil, [{open, i - open} | acc])
    end
  end

  defp masked_runs(shadow, i, nil, acc) when i >= byte_size(shadow), do: Enum.reverse(acc)

  defp masked_runs(shadow, i, open, acc) when i >= byte_size(shadow),
    do: Enum.reverse([{open, i - open} | acc])

  defp safe_slice(bin, start, len) when start + len <= byte_size(bin),
    do: binary_part(bin, start, len)

  defp safe_slice(_bin, _start, _len), do: ""

  @doc "The distinct rules with at least one hit."
  @spec offenders([map()]) :: [module()]
  def offenders(entries), do: entries |> Enum.map(& &1.rule) |> Enum.uniq() |> Enum.sort()

  @doc "One-line rendering of a hit, for a failure message."
  @spec render(map()) :: String.t()
  def render(%{rule: rule, line: line, was: was, now: now}) do
    "  #{inspect(rule)} line #{line}\n    was: #{String.trim(was)}\n    now: #{String.trim(now)}"
  end
end
