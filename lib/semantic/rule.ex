defmodule Credence.Semantic.Rule do
  @moduledoc """
  Behaviour for semantic-level rules that fix compiler warnings.

  Each rule matches specific compiler diagnostics and applies targeted fixes.
  Diagnostics come from `Code.with_diagnostics/1` and have the shape:

      %{message: String.t(), position: {line, col} | line, severity: :warning | :error}
  """

  @callback priority() :: integer()

  @type diagnostic :: %{
          message: String.t(),
          position: {integer(), integer()} | integer(),
          severity: :warning | :error
        }

  @doc "Does this rule handle the given diagnostic?"
  @callback match?(diagnostic()) :: boolean()

  @doc "Convert a matched diagnostic to a Credence issue."
  @callback to_issue(diagnostic()) :: Credence.Issue.t()

  @doc "Fix the source for the given diagnostic. Returns modified source."
  @callback fix(source :: String.t(), diagnostic()) :: String.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour Credence.Semantic.Rule

      @impl true
      def priority, do: 500

      defoverridable priority: 0
    end
  end
end
