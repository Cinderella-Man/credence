defmodule Credence.Syntax.WrapBareModuleAttrsInDefmodule do
  @moduledoc """
  Detects bare module attributes (@doc, @spec) alongside function definitions
  outside a defmodule block and wraps them in `defmodule Solution do ... end`.
  """
  use Credence.Syntax.Rule

  @impl true
  def analyze(source) do
    if has_bare_module_attrs?(source) do
      [
        %Credence.Issue{
          rule: :wrap_bare_module_attrs_in_defmodule,
          message: "Module attributes and function definitions outside defmodule",
          meta: %{line: 1}
        }
      ]
    else
      []
    end
  end

  @impl true
  def fix(source) do
    if has_bare_module_attrs?(source) do
      indented =
        source
        |> String.trim_trailing()
        |> String.split("\n")
        |> Enum.map_join("\n", fn line -> "  " <> line end)

      "defmodule Solution do\n" <> indented <> "\nend\n"
    else
      source
    end
  end

  defp has_bare_module_attrs?(source) do
    has_module_attrs?(source) and has_def?(source) and not has_defmodule?(source)
  end

  defp has_module_attrs?(source) do
    Regex.match?(~r/^\s*@(doc|spec)\b/m, source)
  end

  defp has_def?(source) do
    Regex.match?(~r/^\s*def\b/m, source)
  end

  defp has_defmodule?(source) do
    Regex.match?(~r/^\s*defmodule\b/m, source)
  end
end