defmodule Credence.Pattern.NoRedundantUnderscoreBind do
  @moduledoc """
  Detects `_ = var` bindings in patterns (function heads, case clauses, etc.)
  and simplifies them to just `var`.

  The `_ = var` form matches anything and binds it to `var`, which is
  identical to just `var` — the underscore adds no value.

  ## Bad

      def foo(_ = x), do: x + 1

  ## Good

      def foo(x), do: x + 1
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:=, meta, [{:_, _, nil}, {name, _, ctx}]} = node, acc
        when is_atom(name) and is_atom(ctx) ->
          {node, [build_issue(meta) | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:=, _meta, [{:_, _, nil}, {name, _, ctx}]} = node
      when is_atom(name) and is_atom(ctx) ->
        # Replace _ = var with just var
        elem(node, 2) |> List.last()

      node ->
        node
    end)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_redundant_underscore_bind,
      message:
        "Redundant `_ = var` binding. Use just the variable name instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
