defmodule Credence.Syntax.NoOrphanedModuleAttributes do
  @moduledoc """
  Detects and fixes module attributes (`@moduledoc`, `@spec`, `@doc`) and
  `def` declarations that appear at the top level outside any `defmodule`
  wrapper, which causes compile-time errors in Elixir.
  """
  use Credence.Syntax.Rule

  @impl true
  def analyze(source) do
    case Code.string_to_quoted(source) do
      {:ok, ast} ->
        top_level = extract_top_level(ast)

        if needs_defmodule_wrap?(top_level) do
          [
            %Credence.Issue{
              rule: :no_orphaned_module_attributes,
              message: "Module attributes or function definitions found outside defmodule",
              meta: %{}
            }
          ]
        else
          []
        end

      {:error, _} ->
        []
    end
  end

  @impl true
  def fix(source) do
    case Code.string_to_quoted(source) do
      {:ok, ast} ->
        top_level = extract_top_level(ast)

        if needs_defmodule_wrap?(top_level) do
          indented =
            source
            |> String.trim_trailing("\n")
            |> String.split("\n")
            |> Enum.map(fn
              "" -> ""
              line -> "  " <> line
            end)
            |> Enum.join("\n")

          "defmodule Solution do\n#{indented}\nend\n"
        else
          source
        end

      {:error, _} ->
        source
    end
  end

  defp extract_top_level({:__block__, _, exprs}), do: exprs
  defp extract_top_level(expr), do: [expr]

  defp needs_defmodule_wrap?(top_level) do
    has_defmodule = Enum.any?(top_level, &match?({:defmodule, _, _}, &1))

    if has_defmodule do
      false
    else
      Enum.any?(top_level, fn
        {:@, _, [{attr, _, _} | _]} when attr in [:moduledoc, :spec, :doc] ->
          true

        {:def, _, _} ->
          true

        _ ->
          false
      end)
    end
  end
end