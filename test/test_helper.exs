require Logger

Logger.configure(level: :info)

:logger.update_handler_config(
  :default,
  :formatter,
  Logger.Formatter.new(format: "$date $time [$level] $message\n\n")
)

# Behaviour-equivalence backfill is COMPLETE: every Pattern rule has a real
# equivalence test and no `:equivalence_todo` skeletons remain (enforced by
# `test/equivalence_meta_test.exs`). The exclude is therefore dropped — a newly
# added rule shipped with only a skeleton (or with no equivalence test at all)
# now fails the suite, so coverage cannot silently regress.
# `Credence.QuietFormatter` (test/support) prints only failures + a one-line
# summary — no per-test progress dots, which otherwise scroll a multi-thousand-
# test run off the screen. Swap back to `[ExUnit.CLIFormatter]` to see the dots.
# The `:corpus` over-firing layer (test/corpus/over_firing_test.exs) runs Credence
# over the lib/ of ~10 popular hex packages and asserts it flags nothing (beyond a
# reviewed allowlist of genuinely-legit suggestions). It now runs in the default
# suite: every shipped rule is clean on the corpus, so a newly added rule that
# over-fires on idiomatic real code goes red immediately. The packages are fetched
# once into a gitignored cache on first run (fast parse-only analysis thereafter).
# The `:corpus` tag is kept so the layer can be skipped for a quicker run with:
#     mix test --exclude corpus
# Self-heal non-canonical test fixtures before the suite compiles: plain strings
# with a newline → `"""` heredoc, with a quote → `~S'…'`. Runs after test/support
# compiles and before the `*_test.exs` files are required, so they compile against
# canonical fixtures. Idempotent; a no-op once everything is canonical.
Credence.FixtureHealer.heal_dirs()

# The `:idempotency` layer (test/idempotency_test.exs) sweeps `Credence.fix/1`
# twice over all ~5,200 fix-test fixtures — ~9 minutes, roughly tripling the suite.
# It RUNS BY DEFAULT anyway, like `:corpus` above, and the tag exists only so it can
# be skipped for a quicker local loop:
#
#     mix test --exclude idempotency
#
# It used to be excluded by default for exactly the runtime reason, and that is how
# it went red for three fixtures across four rules and stayed red undetected: the
# only thing left running by default was the fast stale-ledger half, and "idempotency
# green" was read as the whole gate. A layer nobody runs is not a gate. Excluding by
# default puts the burden on remembering; excluding by flag puts it on the person who
# chose to skip it.
#
# NOTHING ELSE IS EXCLUDED HERE. If a layer is too slow to run every time, tag it and
# document the flag — do not add it to this list.
ExUnit.start(formatters: [Credence.QuietFormatter])
