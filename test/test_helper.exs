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
ExUnit.start(formatters: [Credence.QuietFormatter])
