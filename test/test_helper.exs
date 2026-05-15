require Logger

Logger.configure(level: :debug)

:logger.update_handler_config(:default, :formatter,
  Logger.Formatter.new(format: "$date $time [$level] $message\n\n")
)

ExUnit.start()
