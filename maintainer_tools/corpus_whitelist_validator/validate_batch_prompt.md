# Validate one batch of accepted corpus findings

You are auditing a batch of **accepted** findings from the Credence corpus
over-firing whitelist (`test/corpus/accepted_findings.txt`). Each finding was
previously accepted as a behaviour-preserving suggestion on well-reviewed,
idiomatic production code. Your job is to find the ones that should **not** have
been accepted — where the rule over-fires or its auto-fix is unsafe.

A wrapper script runs you once per batch and captures your final message as the
batch report. The batch file path and its size are appended at the very end of
this prompt — read that file first.

## Hard constraints (read-only)
- **Do not edit, create, or delete any file.** No git. This is a read-only
  audit. Your only output is the report you print as your final message.
- **No scratch files / no /tmp.** Verify Elixir semantics with inline
  `elixir -e '...'`; inspect a rule's actual fix output with the helper below.

## What each line means
Every line in the batch file is one finding:

    <corpus-relative path>:<line>  <rule>   [ (xN) ]

The source lives at `corpus/<corpus-relative path>` (already fetched). The rule
is defined in `lib/pattern/<rule>.ex`.

## How to judge a finding
For each finding, decide whether it is a genuine, behaviour-preserving
suggestion or a problem. Flag it only with concrete evidence — not on taste.

1. **Read the rule** `lib/pattern/<rule>.ex` — understand exactly when it fires
   and what its fix produces, plus any documented narrowings.
2. **Read the source** at `corpus/<path>` around the cited line.
3. **See the ACTUAL fix output** — the most reliable check:

       mix run maintainer_tools/corpus_whitelist_validator/showfix.exs <rule> <corpus-relative-path> <line>

   It prints the original context and a unified diff of the rule's real fixed
   output (or `[NO CHANGE]` if the fix is a no-op / self-reverts).

4. **Flag a finding when the fix would:**
   - **not compile** — wrong stdlib arity, a corrupted macro/`defguard` head, a
     dangling reference to a deleted clause, an operator-precedence trap
     (`x |> Enum.reverse() ++ […]`), etc. (it may still *parse* — check meaning,
     not just syntax);
   - **change behaviour** — drops/swaps a guard, shadows a later clause, reorders
     or reduces a side effect, mangles a module attribute (`@x` → `@_x`), changes
     dispatch or error type;
   - **be silly / a no-op** — fires where the rewrite is pointless or self-reverts
     (then it should not be an accepted *finding* at all).

Be efficient: read each distinct rule once, then spot-check its findings and run
`showfix` on anything non-obvious or matching the failure modes above. For a
rule that is clearly fine across the batch, say so rather than belabouring it.

## Output — print ONLY this markdown report as your final message

    ## Batch <batch filename> — <N> findings
    - Distinct rules in batch: <list>
    - VERDICT: clean  |  <K> concern(s) found

    ### FLAGGED
    - `path:line` — `rule` — SEVERITY(high/med/low) — what the fix does wrong,
      with a short diff snippet as evidence.
    (omit this section if none)

    ### Notes
    - patterns, near-misses, or anything worth a human glance (optional)

If every finding in the batch is a sound, behaviour-preserving suggestion, say
so plainly: `VERDICT: clean` and an empty FLAGGED section.
