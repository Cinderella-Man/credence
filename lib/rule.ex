defmodule Credence.Rule do
  @moduledoc """
  Behaviour for all Credence semantic rules.
  """

  @callback check(Macro.t(), keyword()) :: [Credence.Issue.t()]
  @callback fixable?() :: boolean()
  @callback fix(source :: String.t(), opts :: keyword()) :: String.t()

  @optional_callbacks [fix: 2]

  defmacro __using__(_opts) do
    quote do
      @behaviour Credence.Rule

      @impl true
      def fixable?, do: false

      defoverridable fixable?: 0
    end
  end
end
