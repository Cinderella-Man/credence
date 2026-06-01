defmodule Credence.Pattern.NoRedundantDedupBeforeMapset do
  @moduledoc """
  Detects `Enum.dedup/1` or `Enum.uniq/1` used before `MapSet.new/1`,
  making the deduplication a redundant intermediate step.

  `MapSet.new/1` already stores only unique elements, so running
  `Enum.dedup/1` or `Enum.uniq/1` beforehand has no effect.

  ## Bad

      Enum.dedup(items) |> MapSet.new()
      items |> Enum.dedup() |> MapSet.new()
      MapSet.new(Enum.dedup(items))
      Enum.uniq(items) |> MapSet.new()

  ## Good

      MapSet.new(items)
      MapSet.new(items)
      MapSet.new(items)
      MapSet.new(items)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @dedup_funcs [:dedup, :uniq]

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipe form: <dedup> |> MapSet.new(...)
        {:|>, meta, [left, {{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, _, _}]} = node, acc ->
          case extract_dedup_expr(left) do
            {:ok, _} ->
              issue = %Issue{
                rule: :no_redundant_dedup_before_mapset,
                message:
                  "`Enum.dedup/1` (or `Enum.uniq/1`) is redundant when piped into `MapSet.new/1` — " <>
                    "it already stores only unique elements.",
                meta: %{line: Keyword.get(meta, :line)}
              }

              {node, [issue | acc]}

            :error ->
              {node, acc}
          end

        # Non-pipe form: MapSet.new(Enum.dedup(...))
        {{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, meta, [first_arg | _rest]} = node, acc ->
          case extract_dedup_expr(first_arg) do
            {:ok, _} ->
              issue = %Issue{
                rule: :no_redundant_dedup_before_mapset,
                message:
                  "`Enum.dedup/1` (or `Enum.uniq/1`) is redundant inside `MapSet.new/1` — " <>
                    "it already stores only unique elements.",
                meta: %{line: Keyword.get(meta, :line)}
              }

              {node, [issue | acc]}

            :error ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn
        # Pipe form: <dedup> |> MapSet.new() → MapSet.new(expr)
        {:|>, _, [left, {{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, _, _}]} = node, acc ->
          case extract_dedup_expr(left) do
            {:ok, expr} ->
              range = Sourceror.get_range(node)
              change = "MapSet.new(#{Sourceror.to_string(expr)})"
              {node, [%{range: range, change: change} | acc]}

            :error ->
              {node, acc}
          end

        # Non-pipe form: MapSet.new(Enum.dedup(expr)) → MapSet.new(expr)
        {{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, _, [first_arg | _rest]} = node, acc ->
          case extract_dedup_expr(first_arg) do
            {:ok, expr} ->
              range = Sourceror.get_range(first_arg)
              change = Sourceror.to_string(expr)
              {node, [%{range: range, change: change} | acc]}

            :error ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(patches)
  end

  # Enum.dedup(x) or Enum.uniq(x)
  defp extract_dedup_expr({{:., _, [{:__aliases__, _, [:Enum]}, func]}, _, [expr]})
       when func in @dedup_funcs,
       do: {:ok, expr}

  # x |> Enum.dedup() or x |> Enum.uniq()
  defp extract_dedup_expr(
         {:|>, _, [expr, {{:., _, [{:__aliases__, _, [:Enum]}, func]}, _, _}]}
       )
       when func in @dedup_funcs,
       do: {:ok, expr}

  defp extract_dedup_expr(_), do: :error
end
