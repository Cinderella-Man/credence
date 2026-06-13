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
ExUnit.start(formatters: [Credence.QuietFormatter])
