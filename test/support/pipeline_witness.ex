defmodule Credence.PipelineWitness do
  @moduledoc """
  Does a rule's own test fixture make that rule fire **through the real
  pipeline**? (docs/22 T1.)

  ## The failure this exists to catch

  Every existing per-rule gate is either shape-based (it reads the test file's
  AST) or calls the rule directly. Both agree with a rule that is inert in
  production, because nothing in them consults the thing that decides whether a
  rule ever runs: the *phase*.

  A Semantic rule is reached only if the compiler really emits a diagnostic its
  `match?/1` accepts, and only if no earlier rule claims that diagnostic first
  (`Enum.find` — first match wins). A Syntax rule is reached only if the source
  fails to parse, because `Credence.Syntax` does nothing at all on source that
  parses. Neither condition is checked anywhere today, and a test that calls
  `Rule.match?(%{severity: :error, message: "…"})` with a hand-written map
  cannot check them: the rule, the fabricated diagnostic and the assertion are
  three mutually-consistent files that never touch a compiler.

  That is not a hypothetical. Of the 143 rules rejected at acceptance review, 86
  died for exactly these three reasons — a diagnostic the compiler never emits
  (35), a syntax rule whose target parses (18), and a rule shadowed at the
  dispatch slot by a live one (33) — and every one of them passed the harness's
  full Gate first. Measured on the surviving tree: 185 of 185 semantic test files
  fabricate their diagnostic, only 10 of 90 semantic rules ever compile a fixture
  to check the compiler agrees, and 3 of 45 syntax rules assert their input does
  not parse.

  ## What counts as a witness

  A candidate fixture is any string literal in the rule's own test files (see
  `candidates/1`). A rule is *witnessed* when at least one candidate produces an
  issue **attributed to that rule** from `Credence.analyze/2` — the top-level
  entrypoint, full live rule set, real dispatch, real `compile_and_capture`.

  Going through the top level rather than per-sub-gate checks is deliberate. A
  rule can key on a diagnostic that is perfectly real but belongs to another
  rule; it passes a "is this message reachable?" check and dies only end-to-end.
  The witness therefore proves the conjunction: the compiler emits it, the phase
  forwards it, the rule wins its slot, and `should_report?/2` does not decline.

  ## Attribution

  `Credence.RuleName.from_module/1` gives the issue atom for Pattern and
  Semantic rules, and `Credence.Issue.rule` carries it. Syntax atoms are
  author-chosen and unrelated to the module name, so a Syntax rule is attributed
  structurally instead: the phase `flat_map`s over every rule with no dispatch
  contention, so the rule's own `analyze/1` output *is* its contribution to the
  pipeline's issue list, and the witness is that (a) the fixture genuinely fails
  to parse — the whole G2 class — and (b) those issues appear in the pipeline
  result.

  ## Cost, and why calling the phase is the same call

  A Semantic candidate costs one `Code.compile_string`; a Pattern one costs a
  parse plus all 155 Pattern rules. Probing every rule through
  `Credence.analyze/2` therefore pays for both halves on every candidate of
  either kind — measured at 202 s across the three phases, most of it Pattern
  candidates being compiled for a Semantic round whose output is then discarded.

  That cost buys nothing, because for candidates filtered by parseability the
  phase call and the top-level call are **equal, not merely similar**.
  `Credence.analyze/2` is:

      syntax = Syntax.analyze(code)
      if syntax != [], do: syntax, else: Semantic.analyze(code) ++ Pattern.analyze(code)

  A candidate that parses yields `syntax == []`, so the result is exactly
  `Semantic.analyze(code) ++ Pattern.analyze(code)` — and since issues are
  concatenated, never filtered against each other, an issue attributed to a
  Semantic rule is present iff `Semantic.analyze/2` produced it, independent of
  the Pattern half (and vice versa). A candidate that does not parse yields the
  Syntax branch alone. So each phase is probed through its own `analyze/2`, and
  `PipelineWitnessTest` pins the identity itself so a future change to
  `Credence.analyze/2` cannot quietly invalidate the shortcut.

  Candidates are pre-filtered by parseability, which is nearly free and is also
  the correct filter: a Syntax fixture must NOT parse and a Semantic/Pattern one
  must. The probe stops at the first witness per rule.
  """

  alias Credence.MetaTestSupport
  alias Credence.RuleName

  @phases %{
    pattern: {"test/pattern/**/*_test.exs", :parses},
    semantic: {"test/semantic/**/*_test.exs", :parses},
    syntax: {"test/syntax/**/*_test.exs", :does_not_parse}
  }

  @doc "Every rule of `phase`, in dispatch order."
  def rules(:pattern), do: Credence.Pattern.default_rules()
  def rules(:semantic), do: Credence.Semantic.default_rules()
  def rules(:syntax), do: Credence.Syntax.default_rules()

  @doc """
  Candidate fixtures for `rule`: every string literal appearing in any test file
  that references it, filtered to those with the parseability its phase requires.

  Deliberately broader than `MetaTestSupport.fixtures/1`, which only sees strings
  in known verb/variable positions and misses the 49 Pattern + 28 Semantic files
  that bind their fixture to a module attribute. Over-collection is safe here —
  a witness only has to be found once — and is bounded by the parse filter.
  """
  def candidates(rule) do
    rule
    |> phase_of()
    |> index()
    |> Map.get(String.to_atom(MetaTestSupport.short(rule)), [])
  end

  @doc """
  `%{rule_short_atom => [candidate_source]}` for `phase`, built once and cached.

  The cache is not an optimisation detail, it is the difference between a usable
  gate and an unusable one. Built naively — walking the glob per rule — this is
  quadratic in a way that does not look it: 155 Pattern rules x 472 test files is
  73,000 Sourceror parses of the same files, and it dominated everything else
  (135 s for Pattern, against ~1 s of actual probing). Each file is now parsed
  once, its string literals extracted once, and filed under every rule it
  references.

  Cached in `:persistent_term` because the test files cannot change during a run:
  `Credence.FixtureHealer.heal_dirs/0` rewrites fixtures in `test_helper.exs`,
  before any test file is loaded.
  """
  def index(phase) do
    key = {__MODULE__, :index, phase}

    case :persistent_term.get(key, nil) do
      nil ->
        built = build_index(phase)
        :persistent_term.put(key, built)
        built

      built ->
        built
    end
  end

  defp build_index(phase) do
    {glob, parseability} = Map.fetch!(@phases, phase)

    glob
    |> Path.wildcard()
    |> Enum.flat_map(&file_entry(&1, parseability))
    |> Enum.reduce(%{}, fn {atoms, strings}, acc ->
      Enum.reduce(atoms, acc, &Map.update(&2, &1, strings, fn prior -> prior ++ strings end))
    end)
    |> Map.new(fn {atom, strings} -> {atom, Enum.uniq(strings)} end)
  end

  defp file_entry(path, parseability) do
    case MetaTestSupport.load_ast(path) do
      {:ok, ast} ->
        strings =
          ast
          |> string_literals()
          |> Enum.uniq()
          |> Enum.filter(&plausible_code?/1)
          |> Enum.filter(&matches_parseability?(&1, parseability))

        if strings == [], do: [], else: [{referenced_atoms(ast), strings}]

      :error ->
        []
    end
  end

  # Every module reference's last segment — the same relation
  # `MetaTestSupport.references_rule?/2` tests one rule at a time, inverted so
  # the file is read once instead of once per rule.
  defp referenced_atoms(ast) do
    {_ast, acc} =
      Macro.prewalk(ast, [], fn
        {:__aliases__, _, parts} = node, acc when is_list(parts) ->
          {node, [List.last(parts) | acc]}

        node, acc ->
          {node, acc}
      end)

    acc |> Enum.filter(&is_atom/1) |> Enum.uniq()
  end

  @doc """
  Probe `rule` against its own fixtures through `Credence.analyze/2`.

  Returns `{:witnessed, fixture}` for the first candidate that produces an issue
  attributed to this rule, or `{:unwitnessed, reason}` where reason distinguishes
  a rule with nothing to probe from one probed and never seen.
  """
  def witness(rule) do
    case candidates(rule) do
      [] -> {:unwitnessed, :no_candidates}
      candidates -> probe(rule, candidates)
    end
  end

  defp probe(rule, candidates) do
    Enum.reduce_while(candidates, {:unwitnessed, {:not_seen, length(candidates)}}, fn code, acc ->
      if fires_through_pipeline?(rule, code), do: {:halt, {:witnessed, code}}, else: {:cont, acc}
    end)
  end

  @doc """
  Does `code` make `rule` fire through `Credence.analyze/2`?

  All assumptions are switched on explicitly rather than relying on `:default`,
  so a rule gated behind an assumption is not scored as dead, and a global
  `assumptions: :strict` left in the application env by another test cannot
  silently empty the rule set.
  """
  def fires_through_pipeline?(rule, code) do
    case phase_of(rule) do
      # Structural attribution: a Syntax rule's atom is author-chosen, but the
      # phase concatenates without contention, so "this rule contributed" is
      # exactly "the phase, restricted to it, reported something" — and the
      # phase reports nothing at all on source that parses, which is the G2 class.
      :syntax -> phase_issues(:syntax, code, rule) != []
      :semantic -> attributed?(rule, phase_issues(:semantic, code))
      :pattern -> attributed?(rule, phase_issues(:pattern, code, rule))
    end
  end

  @doc """
  The issues `phase` produces for `code`, as `rule` would see them. See the
  moduledoc for why calling the phase equals calling `Credence.analyze/2`.

  **The rule set differs by phase, and that difference is the point.**

  `Credence.Pattern.analyze/2` and `Credence.Syntax.analyze/2` both `flat_map`
  over their rules and concatenate: no rule can suppress, shadow or consume
  another's finding, so one rule's contribution to the full run is exactly what
  it produces alone. Passing `rules:`/`syntax_rules:` is therefore an identity,
  and a 155x cheaper one (the full-set probe measured 135 s for Pattern alone;
  this is ~1 s).

  `Credence.Semantic.analyze/2` is **not** like that. It dispatches
  first-match-wins (`Enum.find`), so a rule is reached only if no earlier rule
  claims the diagnostic. Narrowing the rule set there would hand every rule an
  uncontested slot and silently delete the G3 dispatch-loser class — 33 of the
  86 rejects this gate exists to catch. Semantic is always probed against the
  full live rule set, and `PipelineWitnessTest` pins that it is.
  """
  def phase_issues(phase, code, rule \\ nil) do
    assumptions = [assumptions: all_assumptions_on()]

    safely(
      fn ->
        case {phase, rule} do
          {:syntax, nil} -> Credence.Syntax.analyze(code, assumptions)
          {:syntax, r} -> Credence.Syntax.analyze(code, [syntax_rules: [r]] ++ assumptions)
          {:pattern, nil} -> Credence.Pattern.analyze(code, assumptions)
          {:pattern, r} -> Credence.Pattern.analyze(code, [rules: [r]] ++ assumptions)
          # Never narrowed — see above.
          {:semantic, _} -> Credence.Semantic.analyze(code, assumptions)
        end
      end,
      []
    )
  end

  defp attributed?(rule, issues) do
    atom = RuleName.from_module(rule).atom
    Enum.any?(issues, &(&1.rule == atom))
  end

  @doc "Every registered assumption switched on, so no rule is filtered out."
  def all_assumptions_on, do: Map.new(Credence.Assumptions.names(), &{&1, true})

  # A rule's fixtures can be pathological by design (that is what they are for),
  # and a probe whose job is to measure must not itself become a way to fail the
  # suite. A raising candidate is simply not a witness.
  defp safely(fun, default) do
    fun.()
  rescue
    _ -> default
  catch
    _, _ -> default
  end

  # --- extraction -------------------------------------------------------------

  # Every string literal in the tree, wherever it sits — inline verb argument,
  # `=`-bound variable, or module attribute. Sourceror keeps the delimiter in the
  # node's metadata, which is what separates a real string literal from an atom
  # or an identifier that happens to hold a binary.
  #
  # Both the raw text and its unescaped form are emitted, because Sourceror
  # hands back the literal as it appears IN THE FILE, escapes intact. A fixture
  # for a default-argument rule is written `def greet(a \\\\ 1)` in the test
  # source and its runtime value is `def greet(a \\ 1)`; only the latter parses.
  # Taking the raw form alone silently dropped every fixture containing a
  # backslash — which is every fixture belonging to the default-args rules, so
  # they scored as unwitnessed while being perfectly alive. A `~S` sigil is
  # already raw and unescaping it is a no-op, so emitting both is uniform.
  defp string_literals(ast) do
    {_ast, acc} =
      Macro.prewalk(ast, [], fn node, acc ->
        case node do
          {:__block__, meta, [s]} when is_binary(s) ->
            if Keyword.get(meta, :delimiter), do: {node, forms(s) ++ acc}, else: {node, acc}

          {sigil, _meta, [{:<<>>, _, [s]}, _mods]}
          when sigil in [:sigil_s, :sigil_S] and is_binary(s) ->
            {node, forms(s) ++ acc}

          _ ->
            {node, acc}
        end
      end)

    acc
  end

  # `Macro.unescape_string/1` raises on a literal containing an escape sequence
  # it does not recognise — which a fixture full of deliberately-malformed code
  # can easily contain — so a failure here just means "no unescaped form".
  defp forms(s) do
    case safely(fn -> Macro.unescape_string(s) end, nil) do
      nil -> [s]
      ^s -> [s]
      unescaped -> [s, unescaped]
    end
  end

  # Cheap pre-filter, kept deliberately weak. Its only job is to skip strings
  # that are obviously not source — a bare rule name, a one-word assertion label
  # — because the real filter is parseability, which is both free and exact.
  #
  # An earlier version demanded a keyword or a bracket, and that was a bug with
  # teeth: it dropped `"x = 1e-10"` and `"x = 5e-3"`, which are the *entire*
  # fixture set of `Syntax.FixScientificNotation`, and reported a live rule as
  # having no fixtures at all. A pre-filter in front of a correctness gate must
  # never be cleverer than the gate; when it guesses wrong it manufactures
  # exactly the accusation the gate exists to make truthfully.
  defp plausible_code?(s), do: String.length(s) > 4 and Regex.match?(~r/[^\w\s]/, s)

  defp matches_parseability?(s, :parses), do: match?({:ok, _}, Sourceror.parse_string(s))

  defp matches_parseability?(s, :does_not_parse),
    do: not match?({:ok, _}, Sourceror.parse_string(s))

  @doc "Which phase `rule` belongs to."
  def phase_of(rule) do
    case Module.split(rule) do
      ["Credence", "Pattern" | _] -> :pattern
      ["Credence", "Semantic" | _] -> :semantic
      ["Credence", "Syntax" | _] -> :syntax
    end
  end
end
