require Logger

Logger.configure(level: :info)

:logger.update_handler_config(
  :default,
  :formatter,
  Logger.Formatter.new(format: "$date $time [$level] $message\n\n")
)

# `:equivalence_todo` tags un-filled behaviour-equivalence backfill skeletons
# (see maintainer_tools/gen_equivalence_skeletons.exs). Excluded by default so
# the suite stays green during backfill; the gate un-excludes them at the end.
ExUnit.start(exclude: [:equivalence_todo])
