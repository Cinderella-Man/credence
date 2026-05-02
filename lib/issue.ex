defmodule Credence.Issue do
  @moduledoc """
  Defines the structured issue format for any rule violations.
  """
  defstruct [:rule, :message, meta: %{}]

  @type t :: %__MODULE__{
          rule: atom(),
          message: String.t(),
          meta: map()
        }
end
