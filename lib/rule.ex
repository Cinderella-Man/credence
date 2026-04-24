defmodule Credence.Rule do
  @moduledoc """
  Behaviour for all Credence semantic rules.
  """
  @callback check(Macro.t(), keyword()) :: [Credence.Issue.t()]
end
