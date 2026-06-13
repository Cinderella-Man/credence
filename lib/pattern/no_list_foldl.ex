defmodule Credence.Pattern.NoListFoldl do
  @moduledoc """
  Detects `List.foldl/3` and suggests `Enum.reduce/3` instead.

  `List.foldl(list, acc, fun)` and `Enum.reduce(list, acc, fun)` are identical —
  same left-to-right order, same `fun.(elem, acc)` argument order — so the rewrite
  is a direct, behavior-preserving swap. `Enum.reduce/3` is the idiomatic Elixir
  fold; `List.foldl/3` usually signals code ported from Erlang/Haskell.

  `List.foldr/3` is intentionally **not** covered: it is a *right* fold, so an
  equivalent rewrite needs `Enum.reduce(Enum.reverse(list), acc, fun)`, which is
  more verbose than the already-clear `List.foldr`.

  ## Bad

      List.foldl(list, acc, fun)

      list |> List.foldl(acc, fun)

  ## Good

      Enum.reduce(list, acc, fun)

      list |> Enum.reduce(acc, fun)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case extract_foldl(node) do
          {:ok, meta} ->
            issue = %Issue{
              rule: :no_list_foldl,
              message: "`List.foldl/3` is non-idiomatic; use `Enum.reduce/3` instead.",
              meta: %{line: Keyword.get(meta, :line)}
            }

            {node, [issue | issues]}

          :error ->
            {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      # Piped: source |> List.foldl(acc, fun) → source |> Enum.reduce(acc, fun)
      {:|>, pipe_meta, [source, {{:., _, [mod, :foldl]}, _call_meta, args}]} = node
      when is_list(args) ->
        if list_module?(mod) do
          {:|>, pipe_meta, [source, enum_reduce_call(args)]}
        else
          node
        end

      # Direct: List.foldl(list, acc, fun) → Enum.reduce(list, acc, fun)
      {{:., _, [mod, :foldl]}, _meta, [_list, _acc, _fun] = args} = node ->
        if list_module?(mod), do: enum_reduce_call(args), else: node

      node ->
        node
    end)
  end

  defp enum_reduce_call(args) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :reduce]}, [], args}
  end

  defp extract_foldl({{:., meta, [mod, :foldl]}, _, args}) when is_list(args) do
    if list_module?(mod), do: {:ok, meta}, else: :error
  end

  defp extract_foldl(_), do: :error

  defp list_module?({:__aliases__, _, [:List]}), do: true
  defp list_module?(_), do: false
end
