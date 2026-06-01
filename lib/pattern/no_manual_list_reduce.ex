# Placeholder — rule was removed; kept as empty module to avoid compilation errors.
defmodule Credence.Pattern.NoManualListReduce do
  @moduledoc false
  use Credence.Pattern.Rule

  @impl true
  def check(_ast, _opts), do: []

  @impl true
  def fix_patches(_ast, _opts), do: []
end
