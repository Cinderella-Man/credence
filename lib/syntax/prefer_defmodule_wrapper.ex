defmodule Credence.Syntax.PreferDefmoduleWrapper do
  @moduledoc """
  Detects bare module attributes (`@doc`, `@spec`, etc.) and function definitions
  (`def`, `defp`) outside a `defmodule` wrapper, which produces compile-time errors
  like `cannot invoke @/1 outside module`. The fix wraps the offending code in a
  `defmodule Solution do ... end` block.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @impl true
  def analyze(source) do
    case Code.string_to_quoted(source) do
      {:ok, ast} ->
        top_level = flatten_block(ast)

        if needs_defmodule_wrapper?(top_level) do
          [
            %Issue{
              rule: :prefer_defmodule_wrapper,
              message: "Module attributes and function definitions must be inside a defmodule",
              meta: %{line: 1}
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
        top_level = flatten_block(ast)

        if needs_defmodule_wrapper?(top_level) do
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

  defp flatten_block({:__block__, _meta, nodes}), do: nodes
  defp flatten_block(node), do: [node]

  defp needs_defmodule_wrapper?(top_level_nodes) do
    has_module_attrs? = Enum.any?(top_level_nodes, &match?({:@, _, _}, &1))
    has_defs? = Enum.any?(top_level_nodes, &match?({:def, _, _}, &1))
    has_defps? = Enum.any?(top_level_nodes, &match?({:defp, _, _}, &1))
    has_defmodule? = Enum.any?(top_level_nodes, &match?({:defmodule, _, _}, &1))

    (has_module_attrs? || has_defs? || has_defps?) && !has_defmodule?
  end
end