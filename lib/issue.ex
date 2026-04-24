defmodule Credence.Issue do
  @moduledoc """
  Defines the structured issue format for any rule violations.
  """
  defstruct [:rule, :severity, :message, meta: %{}]

  @type t :: %__MODULE__{
          rule: atom(),
          severity: :low | :medium | :high | :critical,
          message: String.t(),
          meta: map()
        }
end
