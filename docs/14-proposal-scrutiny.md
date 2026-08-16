# 14 — Adversarial scrutiny of the docs/12 + docs/13 + harness proposals

> **This document is a SPEC and a HISTORY, not a tracker.** Open work that
> came out of it lives in [`docs/22-remaining-work.md`](22-remaining-work.md),
> and the ordered release map is [`STATUS.md`](../STATUS.md). Where this file
> describes something as open, check there before believing it.

**Status:** validation report · **Date:** 2026-07-11 · **Method:** devil's-
advocate review of the improvement proposals in `docs/12`, `docs/13`, and
`credence-evolution-harness/docs/IMPROVEMENTS.md`, by **experiment** — every
load-bearing assumption that could be prototyped was prototyped on this
machine (32 schedulers, Elixir 1.20.2). All repo edits made during the
experiments were reverted; both trees verified clean afterwards.

Verdict legend: **UPHELD** (evidence confirms as written) · **REVISED**
(direction right, numbers/mechanism corrected) · **REFUTED** (claim wrong,
proposal changed).

| # | Experiment | Proposal(s) tested | Verdict |
|---|---|---|---|
| E1 | Battery-hole probe: add max-tie inputs, run all 178 equivalence tests | C1, C2.1 | **UPHELD + new defect found** |
| E2 | Gold over-fire oracle dry-run over all 304 dataset golds | H1 | **REVISED** (premise false as stated) |
| E2b | Executable fix-safety, end-to-end on a real gold + its harness | H2 | **UPHELD, cheaper than claimed** |
| E3 | Per-rule independence: full analyze vs union of 146 single-rule analyzes | P3 | **UPHELD** (0 mismatches) |
| E3b | Scoped-scan timing, incl. `unsafe_in_dsl` worst case | P3 | **REVISED** (numbers) |
| E4 | ExUnit module-per-entry prototype, 3 variants + chunk-size sweep | P1 | **REVISED** (mechanism emphasis) |
| E5 | Neutered-mutant redundancy: blind/no-op mutants of pattern + syntax rules | H4 | **REVISED** (scoped down) |
| E6 | Hand-run semantic mutants of a rule matcher vs its test triplet | C18 | **UPHELD + caveat demonstrated** |
| E7 | Double-fix idempotency sweep over 82 golds with findings | C7 | **REVISED** (rare; cross-round, not intra-Pattern) |
| E8 | Novelty residual-rescue through the real `mix credence.covers` | H7 | **REVISED** (my rescue branch was unsound) |

---

## E1 — The battery probe found a second live defect (C1/C2 upheld)

Adding two mixed-kind max-tie entries (`[1.0, 1]`, `[1, 2, 2.0]`) to
`term_lists()` (+ tie entries to `stability_lists()`) and re-running the full
equivalence suite (178 tests, 0.8 s):

- **`NoSortThenAt` went red** on `[1.0, 1]` — the already-confirmed C1 bug;
  the probe works as a positive control.
- **`NoSortForTopK` went red** on `[1.0, 1]` — a **previously unknown shipped
  defect**: its `sort |> reverse |> at(0)` → `Enum.max(...)` mapping has the
  same first-vs-last-maximal tie divergence. Nobody — not the rule author, the
  equivalence backfill, or the rule-quality audit — had flagged this rule.
- `no_sort_then_reverse` / `no_double_sort_same_list` **stayed green** even
  with `===`-distinct ties in their stability battery — double-confirming the
  earlier brute-force result that those two are safe on 1.20.2 (and that the
  C1 sentinel-test recommendation, not a rewrite, is the right action there).

**Consequence:** C1's scope grows to `NoSortForTopK` (same strict-sorter style
repair). One battery entry → one new real bug in 0.8 s is the entire C2 thesis
in miniature.

## E2 — H1's "gold = zero findings" premise is FALSE; redesign as a ratchet

Running full `Pattern.analyze` over all 304 dataset gold solutions:
**76 golds (25%) produce 124 findings across 20 rules** (top:
`prefer_erlang_float` 37, `no_cond_two_clauses` 18,
`no_eager_with_index_in_reduce` 17, `prefer_guard_over_if` 11). 6 parse-fails
are the known multi-file bundles; zero crashes. Inspection splits the findings
into (a) genuine gold non-idiomatics (e.g. eager `with_index` in reduce — a
fair performance nit) and (b) taste-rule noise (`prefer_erlang_float` firing
37× on one hand-author's deliberate `* 1.0` coercions — a fresh, independent
signal for the C13 precision-budget list).

**Consequence for H1:** DESIGN §12's "any rewrite of gold = a rule bug →
BUGFIX lane" would flag a quarter of all tasks and drown the lane. The oracle
must be built **exactly like the corpus layer**: an accepted-gold-findings
snapshot, with per-rule **new** findings as the signal. Silver lining: the full
scan of all 304 golds took **1.1 s** (parallel) — the oracle is ~400× cheaper
than the corpus scan, so running it at the Gate per candidate is trivially
affordable.

## E2b — H2 works end-to-end and is cheaper than proposed

Applied `no_eager_with_index_in_reduce`'s fix to a real gold
(`Enum.with_index()` → `Stream.with_index()`), then ran the task's own
14-test harness against the fixed module **standalone**
(`elixir -e 'ExUnit.start(); Code.compile_file(sol); Code.compile_file(harness)'`):
**14/14 green in 0.6 s wall**, no workspace, no `mix`. For the pure-OTP
majority of tasks, H2's per-subject cost is sub-second, not the ~5 s
mix-test estimate in the proposal; only dep-needing tasks require the
workspace. H2 stands, with a cheaper default runner.

## E3 — P3's soundness assumption holds empirically; its numbers needed fixing

- **Independence:** over 44 corpus files (29 with findings), the full
  146-rule `Pattern.analyze` finding set equals the union of 146 single-rule
  analyzes **exactly — 0 mismatches**. The scoped-scan decomposition is sound
  in practice, not just by code reading.
- **Timing correction:** the single-rule scan measured **~19 ms/file** in this
  session vs the ~8 ms/file published in docs/13 §1 (VM-warmth variance
  between runs). Treat the honest range as **10–20 ms/file**: a 20k-file
  scoped scan is ~3.5–7 CPU-min serial, **~20–40 s parallel**, and
  **~2–8 s with the P4 AST cache** (decode 1.6 ms/file + ~0.1–1.3 ms check).
  Still a ~10–25× cut vs the full suite; the docs/13 §4 table's "~4–13 s" cell
  should read "~5–40 s depending on cache".
- **`unsafe_in_dsl` worst case + a new micro-fix (E9):** a scoped scan of an
  `unsafe_in_dsl` rule costs ~+30% (PreferErlangFloat 6.0 s vs 4.6 s cheap-safe
  per 240 files) because `reject_dsl_unfixable` computes `fix_patches` even
  when `check` returned `[]` (`lib/pattern.ex:34-41` →
  `lib/rule_helpers.ex:304-325` short-circuits only on the *rule*, not on
  empty issues). Measured: 2,878 wasted `fix_patches` calls on clean files
  across just 12 rules × 240 files. A one-line `if issues == [], do: issues`
  guard removes it — add to docs/13 P7.

## E4 — P1: ExUnit module-level async underdelivers alone; async_stream is the primary lever

Prototyped three real ExUnit variants over the 6-package sample (serial
baseline = today's one-module shape, 10.7 s):

| Variant | Wall | Speedup |
|---|---|---|
| one module, per-entry tests (today) | 10,707 ms | 1× |
| module per entry (6 modules) | 6,559 ms | **1.6×** (biggest-entry floor) |
| chunked modules, 30 files/chunk | 4,741 ms | 2.3× |
| chunked modules, 8 files/chunk | 2,965 ms | **3.6×** |
| pure `Task.async_stream` (from docs/13 §1) | — | **12.6×** |

Module-level async pays scheduling/imbalance overhead and is floored by the
slowest chunk; the in-test `Task.async_stream` is what actually approaches the
machine. **Revised P1 design:** keep (or lightly split) the per-entry test
structure for reporting, and put `Task.async_stream` over files *inside* the
entry tests as the primary parallelism — module splitting is secondary, for
distributing the big repos. The "~45–90 s" projection stands, but via
async_stream-first, not module-count-first.

## E5 — H4's neutered mutants are largely redundant for Pattern rules; scope them

Neutering a healthy pattern rule (`no_uniq_then_count`) both ways and running
its own triplet: blind-check mutant → **7 failures**; no-op-fix mutant →
**7 failures**. A syntax rule (`fix_python_floor_div`) with a no-op fix →
**13/31 failures**. The kills come from the mandatory equivalence test's
precheck (rule must fire + rewrite) and the meta-gated positive/transform
assertions — i.e., **credence's existing gates already dynamically kill
neutered mutants for any rule with a real `assert_equivalent`**. I also
suspected the harness's `mix credence.fix_tests` canonicalizer could launder a
no-op fix into a green tautology — **refuted**: it explicitly refuses to
rewrite when `actual == input` (`lib/mix/tasks/credence.fix_tests.ex:24-27`).

**Consequence for H4:** the Gate's new-rule mutation check is still vacuous
and still worth replacing, but the honest replacement is narrower: run
neutered mutants (a) for the **13 pattern rules using `mark_equivalence_*`
opt-outs** (7 cosmetic / 7 repair / 2 unconstructible — no firing precheck
exists there), (b) for **syntax/semantic rules** as belt-and-braces, and (c)
as a cheap guard against tests that satisfy the meta-gates textually while
asserting nothing real. For ordinary pattern rules the equivalence precheck
already is the mutation kill.

## E6 — C18's semantic mutants work on rule matchers, with the classic caveat

Four hand-made first-order mutants of `no_manual_max`'s matcher vs its
32-test triplet: `:>=`→`:>` killed (14 fails); `:<=`→`:<` killed (4);
dropping `:>=` from the operator guard killed (13); **dropping `:<` from the
guard SURVIVED (0 fails)** — triage shows it is an **equivalent mutant**:
`:</:>` pass `get_comparison_op` but the downstream `max_pattern?` clauses
deliberately reject strict forms (`lib/pattern/no_manual_max.ex:85,129-137`),
so the guard breadth is dead and the mutant changes nothing (it did flag a
minor simplification lead). **Consequence:** C18 stands — the mechanism
discriminates weak-vs-strong pinning at ~5 s per mutant — but the rollout must
budget for equivalent-mutant triage noise, which is exactly why the dataset's
report-only-first discipline is the right template.

## E7 — C7's fixpoint concern is real but rare, and cross-round, not intra-Pattern

Double-fixing all 82 golds with pattern findings (66 changed by fix):
**exactly 1 file was non-idempotent** — and the mechanism was not the
Pattern-ordering hazard docs/12 emphasizes: a Pattern rewrite left a variable
unused, and since Semantic runs *before* Pattern, only a second full `fix`
call catches the new warning (`001_002_fixed_window_counter_01`, pass 2
applied `UnusedVariable`). Zero residual-then-fixable cases, zero reverts.

**Consequence:** C7's cheapest high-value form is (a) the **idempotency gate**
(it would have caught this specimen) and (b) a targeted "re-run Semantic once
if Pattern changed the code" step — a bounded full fixpoint loop remains
correct but drops in urgency (~1.5% incidence on this workload; the alphabetical-
ordering hazard produced zero observed instances).

## E8 — H7's covers-rerun rescue branch was unsound; span-overlap fixes it

A two-smell probe module (covered `sort|>reverse` + an intended-novel
reduce-concat) through the real `mix credence.covers`:

- The "novel" idiom **alone** read COVERED — `NoStringConcatInLoop` already
  rewrites it to `Enum.map_join`. (Accidental but real evidence for the
  breadth of the current ruleset: inventing a clumsy idiom that 146 rules miss
  is genuinely hard.)
- After `Credence.fix`, the fixed probe read **NOVEL** — which exposes the
  flaw in my proposed rescue: `covers(fix(before))` trends NOVEL for *any*
  input, because `fix` output is by construction a fixed point of the current
  ruleset. In the case where an existing rule rewrote the proposal's target
  idiom **differently** than the proposed `after`, the rerun would report
  NOVEL and a duplicate-by-intent would be built.

**Consequence — revised H7 residual algorithm:** rescue a `:covered` proposal
iff the **diff spans** of `before → fix(before)` do **not overlap** the diff
spans of `before → after` (the existing rules' rewrites didn't touch the
proposal's target region); overlapping spans = genuinely covered/conflicting →
block and name the covering rule (from `applied_rules`). The covers-rerun step
is dropped. Also measured: one `mix credence.covers` invocation ≈ 2.0 s wall —
fine per proposal, but batch if it ever moves into a loop.

---

## Net effect on the proposal documents

- **docs/12:** C1 gains `NoSortForTopK` (E1). C7 re-prioritized to
  idempotency-gate + Semantic-after-Pattern re-pass (E7). C18 confirmed with
  the equivalent-mutant caveat (E6). C13 gains `prefer_erlang_float` as a
  candidate (E2).
- **docs/13:** P1 mechanism flipped to async_stream-first (E4). P3 cost range
  corrected to 10–20 ms/file, independence empirically confirmed, and the E9
  one-line `dsl_dropped_ranges` short-circuit added (E3). P4's decode numbers
  re-confirmed.
- **harness IMPROVEMENTS.md:** H1 redesigned as a gold-findings ratchet, not
  zero-findings (E2) — and shown to cost ~1 s. H2 upheld with a cheaper
  standalone runner (E2b). H4 scoped to mark_* rules + syntax/semantic +
  hollow-test insurance (E5). H7's rescue rewritten as span-overlap (E8).

Nothing in the scrutiny weakened the top-level ordering: the executable
oracles (H1-as-ratchet, H2) and the battery/dimension work (C1/C2) remain the
highest-leverage items — E1 and E2 made them *more* concrete, and every
experiment here ran in seconds-to-minutes, which is itself the docs/13 case
in action.

---

# Appendices — full reproduction detail

Everything needed to re-run or extend these experiments without access to the
original session.

## Appendix A — environment and operational warnings

- **Machine:** Linux, `System.schedulers_online() == 32`. **Elixir 1.20.2**
  (`System.version()`), OTP 29 (matches the dataset's `.tool-versions` pin).
- **Repo states:** credence @ `main` (fb6473c), clean apart from these docs.
  Harness @ main, clean apart from `docs/IMPROVEMENTS.md`. Dataset present at
  `~/projects/elixir-sft-dataset` (untouched; one gold was temporarily
  modified during E2b and byte-restored, verified via `git status`).
- **Corpus sample:** 6 pinned packages fetched into the gitignored `corpus/`
  cache exactly as `Credence.Corpus.fetch_one!/1` would:

  ```bash
  for p in "jason 1.4.5" "decimal 3.1.1" "plug 1.19.2" "tesla 1.20.0" \
           "ecto 3.14.0" "phoenix 1.8.8"; do set -- $p
    mix hex.package fetch $1 $2 --unpack --output corpus/$1
  done
  # → 240 lib/**/*.ex files, 2,659,136 bytes (after excluding deps/_build/test)
  ```

  These six are left in `corpus/` — they are a valid warm subset of the real
  cache and will speed a future full fetch.
- **⚠️ `mix test` trap:** a plain `mix test` in credence triggers
  `Corpus.ensure_fetched!()` in every corpus module's `setup_all`, which
  downloads **~465 hex packages and shallow-clones ~37 large repos**
  (Blockscout, Elixir itself, …). On a dev box always run
  `mix test --exclude corpus` unless a full fetch is intended.
- **⚠️ Harness preflight:** `cev` preflight requires the credence clone on
  branch `evolution` with a **clean tree** — the untracked docs added by this
  work must be committed (or the clone repointed) before a harness run.
- All experiments ran under `MIX_ENV=test` (`compiles?`, `BehaviourEquivalence`
  and `EquivalenceInputs` live in `test/support/`). Compile warnings about
  `dsl_guard.ex:396` and `no_list_pop_at_for_access.ex:150` are pre-existing
  and unrelated.

## Appendix B — scripts and commands (verbatim)

### B.1 Baseline benchmark (docs/13 §1 numbers)

Run as `MIX_ENV=test mix run bench.exs` from the credence root with the
corpus sample fetched:

```elixir
files =
  Path.wildcard("corpus/**/lib/**/*.ex")
  |> Enum.reject(&String.contains?(&1, ["/deps/", "/_build/", "/test/", "/node_modules/"]))

srcs = Enum.map(files, &{&1, File.read!(&1)})
IO.puts("files=#{length(srcs)} bytes=#{srcs |> Enum.map(fn {_, s} -> byte_size(s) end) |> Enum.sum()}")

{t_disc, rules} = :timer.tc(fn -> Credence.RuleHelpers.discover_rules(Credence.Pattern.Rule) end)
{t_disc2, _} = :timer.tc(fn -> Credence.RuleHelpers.discover_rules(Credence.Pattern.Rule) end)
IO.puts("discover_rules: #{length(rules)} rules, first=#{t_disc / 1000}ms repeat=#{t_disc2 / 1000}ms")

{t_parse, asts} =
  :timer.tc(fn ->
    Enum.map(srcs, fn {p, s} ->
      case Sourceror.parse_string(s) do
        {:ok, ast} -> {p, s, ast}
        _ -> {p, s, nil}
      end
    end)
  end)

asts = Enum.reject(asts, fn {_, _, a} -> is_nil(a) end)
IO.puts("parse_all=#{Float.round(t_parse / 1000, 1)}ms (#{length(asts)} parsed)")

{t_t2b, bins} = :timer.tc(fn -> Enum.map(asts, fn {_, _, a} -> :erlang.term_to_binary(a, [:compressed]) end) end)
{t_b2t, _} = :timer.tc(fn -> Enum.map(bins, &:erlang.binary_to_term/1) end)
IO.puts("ast_cache: t2b=#{Float.round(t_t2b / 1000, 1)}ms b2t=#{Float.round(t_b2t / 1000, 1)}ms bytes=#{bins |> Enum.map(&byte_size/1) |> Enum.sum()}")

{t_an, n_findings} =
  :timer.tc(fn ->
    srcs |> Enum.map(fn {_, s} -> Credence.Pattern.analyze(s) |> length() end) |> Enum.sum()
  end)

IO.puts("analyze_all(146 rules)=#{Float.round(t_an / 1000, 1)}ms findings=#{n_findings}")

totals =
  Enum.reduce(rules, %{}, fn rule, acc ->
    t =
      Enum.reduce(asts, 0, fn {_, s, ast}, tacc ->
        {t, _} = :timer.tc(fn -> try do rule.check(ast, source: s) rescue _ -> [] end end)
        tacc + t
      end)
    Map.put(acc, rule, t)
  end)

IO.puts("sum_all_checks=#{Float.round(totals |> Map.values() |> Enum.sum() |> Kernel./(1000), 1)}ms")
IO.puts("top 15 slowest rules:")
totals |> Enum.sort_by(fn {_, t} -> -t end) |> Enum.take(15)
|> Enum.each(fn {r, t} -> IO.puts("  #{inspect(r)}: #{Float.round(t / 1000, 1)}") end)

median_rule = totals |> Enum.sort_by(fn {_, t} -> t end) |> Enum.at(div(map_size(totals), 2)) |> elem(0)
{t_single, _} = :timer.tc(fn -> Enum.each(srcs, fn {_, s} -> Credence.Pattern.analyze(s, rules: [median_rule]) end) end)
IO.puts("single_rule_analyze_all (#{inspect(median_rule)}) = #{Float.round(t_single / 1000, 1)}ms")

{t_par, _} =
  :timer.tc(fn ->
    srcs
    |> Task.async_stream(fn {_, s} -> Credence.Pattern.analyze(s) end,
      max_concurrency: System.schedulers_online(), timeout: 120_000, ordered: false)
    |> Stream.run()
  end)
IO.puts("analyze_all_parallel(#{System.schedulers_online()} sched)=#{Float.round(t_par / 1000, 1)}ms")
```

### B.2 E1 — battery probe

Edit `test/support/equivalence_inputs.ex`: append `[1.0, 1]` and
`[1, 2, 2.0]` to `term_lists/0`, and `[1, 1.0, 1]` + `[2.0, 2]` to
`stability_lists/0`. Then:

```bash
MIX_ENV=test mix test test/pattern/*_equivalence_test.exs   # 178 tests, ~0.8s
```

Revert the file afterwards (the probe entries are also the permanent C2.1
recommendation — landing them for real requires triaging every new red as a
genuine divergence).

### B.3 E2 — gold over-fire oracle dry-run

`MIX_ENV=test mix run gold_oracle.exs` from the credence root:

```elixir
golds = Path.wildcard("/home/kamil/projects/elixir-sft-dataset/tasks/*_01/solution.ex") |> Enum.sort()

{t, results} =
  :timer.tc(fn ->
    golds
    |> Task.async_stream(
      fn path ->
        src = File.read!(path)
        task = path |> Path.dirname() |> Path.basename()
        issues = try do Credence.Pattern.analyze(src) rescue e -> [%{rule: {:crash, inspect(e.__struct__)}}] end
        {task, Enum.map(issues, & &1.rule)}
      end,
      max_concurrency: System.schedulers_online(), timeout: 120_000, ordered: false
    )
    |> Enum.map(fn {:ok, r} -> r end)
  end)

findings =
  results
  |> Enum.flat_map(fn {task, rules} ->
    for r <- rules, r != :parse_error, not match?({:crash, _}, r), do: {r, task}
  end)

IO.puts("golds=#{length(results)} time=#{Float.round(t / 1_000_000, 1)}s")
IO.puts("clean=#{Enum.count(results, fn {_, rs} -> rs == [] end)}")
findings |> Enum.frequencies_by(&elem(&1, 0)) |> Enum.sort_by(fn {_, n} -> -n end)
|> Enum.each(fn {r, n} -> IO.puts("  #{n}\t#{r}") end)
```

### B.4 E2b — executable fix-safety, standalone runner

```bash
T=~/projects/elixir-sft-dataset/tasks/007_002_weightedmovingaverage_01
cp $T/solution.ex /tmp/backup.ex
MIX_ENV=test mix run -e '
  path = "'$T'/solution.ex"
  fixed = Credence.RuleHelpers.apply_rule_fix(Credence.Pattern.NoEagerWithIndexInReduce, File.read!(path))
  File.write!(path, fixed)'
time elixir -e "ExUnit.start(); Code.compile_file(\"$T/solution.ex\"); Code.compile_file(\"$T/test_harness.exs\")"
cp /tmp/backup.ex $T/solution.ex     # restore!
```

The standalone runner works for any pure-OTP task; dep-needing tasks (jason/
plug/ecto/stream_data/nimble_csv) need the dataset's or the harness's mix
project instead.

### B.5 E3/E9 — independence, scoped-scan timing, DSL waste

`MIX_ENV=test mix run scoped_scan.exs` (corpus sample fetched):

```elixir
files = Path.wildcard("corpus/**/lib/**/*.ex")
        |> Enum.reject(&String.contains?(&1, ["/deps/", "/_build/", "/test/"]))
srcs = Enum.map(files, &{&1, File.read!(&1)})
rules = Credence.RuleHelpers.discover_rules(Credence.Pattern.Rule)

with_findings = Enum.filter(srcs, fn {_, s} -> Credence.Pattern.analyze(s) != [] end)
sample = with_findings ++ Enum.take_random(srcs -- with_findings, 15)
key = fn issues -> issues |> Enum.map(&{&1.rule, &1.meta[:line]}) |> Enum.sort() end

mismatches =
  Enum.filter(sample, fn {_p, s} ->
    key.(Credence.Pattern.analyze(s)) !=
      rules |> Enum.flat_map(fn r -> Credence.Pattern.analyze(s, rules: [r]) end) |> key.()
  end)
IO.puts("independence mismatches: #{length(mismatches)}")

time_rule = fn rule ->
  {t, _} = :timer.tc(fn -> Enum.each(srcs, fn {_, s} -> Credence.Pattern.analyze(s, rules: [rule]) end) end)
  Float.round(t / 1000, 0)
end
for r <- [Credence.Pattern.NoTrailingNewlineInDoc, Credence.Pattern.NoUnderscoreFunctionName,
          Credence.Pattern.PreferErlangFloat, Credence.Pattern.PreferFunctionCapture],
    do: IO.puts("  #{inspect(r)}: #{time_rule.(r)} ms")

unsafe = Enum.filter(rules, fn r -> r.unsafe_in_dsl() != [] end)
{t_waste, n_calls} =
  :timer.tc(fn ->
    Enum.reduce(srcs, 0, fn {_, s}, acc ->
      case Sourceror.parse_string(s) do
        {:ok, ast} ->
          acc + Enum.count(unsafe, fn r ->
            r.check(ast, source: s) == [] &&
              (try do r.fix_patches(ast, source: s) rescue _ -> [] end; true)
          end)
        _ -> acc
      end
    end)
  end)
IO.puts("E9: #{length(unsafe)} unsafe rules; fix_patches-on-clean-file calls=#{n_calls}, #{Float.round(t_waste / 1000, 0)} ms")
```

### B.6 E4 — ExUnit parallelism prototype

`MIX_ENV=test mix run exunit_parallel.exs <serial|per_entry|chunked>` (chunk
size is the `Enum.chunk_every(N)` literal; the sweep used 30 then 8). Core
technique — dynamic module creation so ExUnit sees many async modules; note
anonymous functions cannot be unquoted into module bodies, hence the named
helper:

```elixir
variant = System.argv() |> List.first() || "serial"

defmodule BenchHelper do
  def analyze_all(files), do: Enum.each(files, fn f -> Credence.Pattern.analyze(File.read!(f)) end)
end

entries =
  "corpus/*" |> Path.wildcard()
  |> Enum.map(fn dir ->
    {Path.basename(dir),
     Path.wildcard("#{dir}/**/lib/**/*.ex")
     |> Enum.reject(&String.contains?(&1, ["/deps/", "/_build/", "/test/"]))}
  end)
  |> Enum.reject(fn {_, fs} -> fs == [] end)

ExUnit.start(autorun: false, max_cases: System.schedulers_online() * 2)

case variant do
  "serial" ->
    contents =
      for {name, files} <- entries do
        quote do
          test unquote("entry #{name}"), do: BenchHelper.analyze_all(unquote(files))
        end
      end
    body = quote do
      use ExUnit.Case, async: true
      unquote_splicing(contents)
    end
    Module.create(BenchSerial, body, Macro.Env.location(__ENV__))

  "per_entry" ->
    for {name, files} <- entries do
      body = quote do
        use ExUnit.Case, async: true
        test "analyze entry", do: BenchHelper.analyze_all(unquote(files))
      end
      Module.create(Module.concat(BenchPerEntry, Macro.camelize(name)), body, Macro.Env.location(__ENV__))
    end

  "chunked" ->
    for {name, files} <- entries,
        {chunk, i} <- files |> Enum.chunk_every(8) |> Enum.with_index() do
      body = quote do
        use ExUnit.Case, async: true
        test "analyze chunk", do: BenchHelper.analyze_all(unquote(chunk))
      end
      Module.create(Module.concat([BenchChunked, Macro.camelize(name), "C#{i}"]), body, Macro.Env.location(__ENV__))
    end
end

{t, result} = :timer.tc(fn -> ExUnit.run() end)
IO.puts("variant=#{variant} wall=#{Float.round(t / 1000, 0)}ms result=#{inspect(result)}")
```

### B.7 E5 — neutered mutants

```bash
R=lib/pattern/no_uniq_then_count.ex; cp $R /tmp/rule.orig
# Mutant A (blind check): shadow with an always-[] clause, keep original renamed
perl -0pi -e 's/def check\(/def check(_a, _o), do: []\n  def check_disabled(/' $R
MIX_ENV=test mix test test/pattern/no_uniq_then_count*      # → 7 failures
cp /tmp/rule.orig $R
# Mutant B (no-op fix)
perl -0pi -e 's/def fix_patches\(/def fix_patches(_a, _o), do: []\n  def fix_patches_disabled(/' $R
MIX_ENV=test mix test test/pattern/no_uniq_then_count*      # → 7 failures
cp /tmp/rule.orig $R
# Syntax rule variant
R=lib/syntax/fix_python_floor_div.ex; cp $R /tmp/srule.orig
perl -0pi -e 's/def fix\(/def fix(s), do: s\n  def fix_disabled(/' $R
MIX_ENV=test mix test test/syntax/fix_python_floor_div*     # → 13/31 failures
cp /tmp/srule.orig $R
```

Count of equivalence opt-outs (where the precheck kill does NOT apply):
`grep -rh "mark_equivalence_\w*" test/pattern/*_equivalence_test.exs -o | sort | uniq -c`
→ 7 `mark_equivalence_cosmetic`, 7 `mark_equivalence_repair`,
2 `mark_equivalence_unconstructible` across 13 files.

### B.8 E6 — semantic mutants of a matcher

```bash
R=lib/pattern/no_manual_max.ex; cp $R /tmp/nmm.orig
sed -i '129s/:>=/:>/'  $R; MIX_ENV=test mix test test/pattern/no_manual_max*; cp /tmp/nmm.orig $R  # 14 fails
sed -i '133s/:<=/:</'  $R; MIX_ENV=test mix test test/pattern/no_manual_max*; cp /tmp/nmm.orig $R  #  4 fails
sed -i '85s/\[:>, :>=, :<, :<=\]/[:>, :>=, :<=]/' $R; MIX_ENV=test mix test test/pattern/no_manual_max*; cp /tmp/nmm.orig $R  # 0 fails — equivalent mutant
sed -i '85s/\[:>, :>=, :<, :<=\]/[:>, :<, :<=]/'  $R; MIX_ENV=test mix test test/pattern/no_manual_max*; cp /tmp/nmm.orig $R  # 13 fails
```

The dataset repo's `lib/gen_task/mutation.ex:119-201`
(`semantic_mutants/2`: comparison swap, ±1, `:ok`↔`:error`, boolean flip,
cap 40) is the production-grade generator to port for C18.

### B.9 E7 — double-fix idempotency sweep

`MIX_ENV=test mix run fixpoint.exs` — for every dataset gold with pattern
findings: `r1 = Credence.fix(src)`; if changed, `r2 = Credence.fix(r1.code)`;
record `r2.code != r1.code` (non-idempotent, capture `r2.applied_rules`),
`r1.issues != [] and r2.issues == []` (residual-then-fixable), and any
`:reverted` entries. Serial on purpose — `Code.compile_string` runs in-process
and concurrent compiles of user modules race on purge.

### B.10 E8 — covers probe

```bash
cat > /tmp/two_smell.exs <<'EOF'
defmodule Probe do
  def sorted_desc(l), do: Enum.sort(l) |> Enum.reverse()
  def join_dash(l), do: Enum.reduce(l, "", fn x, acc -> acc <> to_string(x) <> "-" end)
end
EOF
mix credence.covers /tmp/two_smell.exs        # COVERED (~2.0s wall per invocation)
mix run -e 'File.write!("/tmp/fixed.exs", Credence.fix(File.read!("/tmp/two_smell.exs")).code)'
mix credence.covers /tmp/fixed.exs            # NOVEL — because fix output is a fixed point
```

### B.11 Sort-tie verifications (C1, feeding docs/12's appendix)

```bash
elixir -e '
vals = [1, 1.0, 2, 2.0, 0]
lists = for a <- vals, b <- vals, c <- vals, d <- vals, do: [a,b,c,d]
IO.inspect(Enum.count(lists, fn l -> (l |> Enum.sort() |> Enum.reverse()) !== Enum.sort(l, :desc) end), label: "sort|>rev vs :desc divergences (625 lists)")
vals2 = [1, 1.0, 2, 2.0]
lists2 = [[]] ++ for a <- vals2, b <- vals2, c <- vals2, do: [a,b,c]
IO.inspect(Enum.count(lists2, fn l -> Enum.max(l, &>/2, fn -> nil end) !== (Enum.sort(l) |> Enum.at(-1)) end), label: "strict-max vs sort|>at(-1) divergences (65 lists)")
IO.inspect(Enum.count(lists2, fn l -> Enum.max(l, fn -> nil end) !== (Enum.sort(l) |> Enum.at(-1)) end), label: "current-fix divergences")
'
# → 0, 0, 20  (the 20 are the live bug; strict sorter is exact; :desc ≡ reverse)
```

Completeness note: integer-vs-float is the **only** `==`-equal /
`===`-distinct value class in Elixir, so brute-forcing int/float tie lists
covers the entire divergence class — this is why "0 over these lists" is a
proof, not a sample.

## Appendix C — raw data

### C.1 Baseline benchmark output (B.1, 240 files / 2,659,136 bytes)

```
discover_rules: 146 rules, first=160.798ms repeat=0.241ms
parse_all=3379.8ms (240 parsed)
ast_cache: t2b=287.1ms b2t=387.0ms bytes=2527516
analyze_all(146 rules)=12827.5ms findings=44
sum_all_checks=14923.8ms          (includes ~35k :timer.tc call overheads)
single_rule_analyze_all (NoTrailingNewlineInDoc) = 1908.0ms   (maximally warm VM)
analyze_all_parallel(32 sched)=1014.6ms
```

Top-15 slowest rules (cumulative check ms over 240 pre-parsed files — note
the flat distribution; 146-rule mean ≈ 102 ms):

```
NoUnderscoreFunctionName 304.6 · PreferNoQuestionMarkForNonBoolean 288.4 ·
PreferErlangFloat 251.1 · NoLengthComparisonForEmpty 248.2 ·
NoDuplicateFunctionClauses 221.7 · NoRedundantAssignment 219.1 ·
NoRedundantBinarySyntax 202.9 · RedundantListGuard 185.9 ·
PreferFunctionCapture 173.4 · NoRedundantUnderscoreBind 172.8 ·
NoUnusedUnderscoreAssignment 168.2 · NoUnlessElse 164.5 ·
NoKeywordGetIntegerKey 161.8 · NoHdTlWhenConsBound 160.9 · HallucinatedGuard 160.5
```

### C.2 E1 output

```
baseline: 178 tests, 0 failures (0.8s)
with probe entries: 178 tests, 2 failures
  1) NoSortThenAtEquivalenceTest  — behaviour changed in NoSortThenAt on input [1.0, 1]
  2) NoSortForTopKEquivalenceTest — behaviour changed in NoSortForTopK on input [1.0, 1]
     (its `sort |> reverse |> at(0)` → `Enum.max(_, fn -> nil end)` mapping)
```

### C.3 E2 output — gold findings, full histogram (304 golds, 1.1 s)

```
clean=222  parse_fail=6 (the <file>-bundle solutions)  crashes=0
124 findings on 76 golds, 20 rules:
  37 prefer_erlang_float        18 no_cond_two_clauses
  17 no_eager_with_index_in_reduce   11 prefer_guard_over_if
  10 prefer_map_new_with_transform    7 no_length_comparison_for_empty
   4 no_case_true_false                3 no_case_boolean_result
   3 prefer_enum_reverse_two           2 no_kernel_op_in_pipeline
   2 no_map_then_aggregate             2 no_zip_then_map
   1 each: no_case_on_param_dispatch, no_doc_false_on_private,
     no_redundant_assignment, no_redundant_comparison_guard,
     no_redundant_list_traversal, no_unused_underscore_assignment,
     prefer_function_capture, prefer_map_new
```

Sample sites inspected: `prefer_erlang_float` on
`003_001_leaky_bucket_token_dispenser_01` fires on deliberate float coercions
(`%Bucket{tokens: capacity * 1.0, …}`, `min(capacity * 1.0, …)`) — taste-rule
signal; `no_eager_with_index_in_reduce` on `007_002_weightedmovingaverage_01`
is a fair performance nit (fix verified behaviour-preserving in E2b).

### C.4 E3/E9 output (second session, warm — note ×2 variance vs C.1)

```
independence sample: 44 files (29 with findings) → mismatches: 0
scoped scan over 240 files:
  safe cheap  (NoTrailingNewlineInDoc):   4574 ms   (~19 ms/file)
  safe costly (NoUnderscoreFunctionName): 5044 ms
  unsafe_in_dsl (PreferErlangFloat):      6024 ms   (+30%)
  unsafe_in_dsl (PreferFunctionCapture):  5780 ms
E9: 12 unsafe rules; fix_patches-on-clean-file calls=2878 (of 12×240=2880 possible)
```

### C.5 E4 output

```
serial (one module, per-entry tests):  10,707 ms   1.0×
per_entry (6 async modules):            6,559 ms   1.6×
chunked, 30 files/module (11 modules):  4,741 ms   2.3×
chunked,  8 files/module (33 modules):  2,965 ms   3.6×
(reference: raw Task.async_stream compute = 1,015 ms = 12.6×)
```

### C.6 E5 output

```
Pattern no_uniq_then_count, blind-check mutant:  24 tests, 7 failures
  (6 CheckTest positives + 1 EquivalenceTest precheck "rule must fire")
Pattern no_uniq_then_count, no-op-fix mutant:    24 tests, 7 failures
  (6 FixTest transforms + 1 EquivalenceTest precheck "a rewrite must happen")
Syntax fix_python_floor_div, no-op-fix mutant:   31 tests, 13 failures
fix_tests canonicalizer no-op guard: lib/mix/tasks/credence.fix_tests.ex:24-27 (refuses actual==input)
```

### C.7 E6 output (`no_manual_max`, 32-test triplet)

```
M1 line 129 :>= → :>   (matcher accepts strict form):  14 failures — killed
M2 line 133 :<= → :<                                    4 failures — killed
M3 line  85 drop :< from op guard:                      0 failures — SURVIVOR
   triage: equivalent mutant — get_comparison_op admits :</:> but
   max_pattern?/5 only has :>= and :<= clauses (:129-137); strict forms are
   deliberately unmatched (moduledoc tie analysis), so the guard breadth is dead
M4 line  85 drop :>=:                                  13 failures — killed
```

### C.8 E7 output

```
golds with pattern findings: 82 · fix changed code: 66
NON-IDEMPOTENT (fix(fix) != fix): 1
  001_002_fixed_window_counter_01 — pass 2 applied [{"UnusedVariable", 1}]
  (a Pattern rewrite orphaned a variable; Semantic runs BEFORE Pattern, so the
   new warning is only caught by a second full fix — a cross-ROUND gap)
residual-then-fixable: 0 · reverted rules during fix: 0
```

### C.9 E8 transcript

```
novel-only probe (reduce string-concat):  COVERED   ← NoStringConcatInLoop already owns it
two-smell probe:                          COVERED   (NoSortThenReverse + NoStringConcatInLoop fire)
Credence.fix(two_smell) applied: NoSortThenReverse(1), NoStringConcatInLoop(1)
covers(fixed):                            NOVEL     ← fix output is a ruleset fixed point;
                                                      hence the covers-rerun rescue is non-discriminating
mix credence.covers wall time: ~2.0 s per invocation
```
