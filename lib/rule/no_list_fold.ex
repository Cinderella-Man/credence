defmodule Credence.Rule.NoListFold do
  @moduledoc """
  Detects usage of `List.foldl/3` and `List.foldr/3` and suggests
  `Enum.reduce/3` instead.

  ## Why this matters

  `Enum.reduce/3` is the idiomatic Elixir way to fold over a collection.
  While `List.foldl/3` and `List.foldr/3` exist in Elixir's standard
  library, they are rarely used in practice and signal code ported from
  Erlang (`:lists.foldl`) or Haskell.

  LLMs frequently generate `List.foldl` because their training data
  includes heavy Erlang and Haskell influence. The resulting code is
  functionally correct but non-idiomatic, which reduces readability for
  Elixir developers.

  ## Flagged patterns

  | Pattern              | Suggested replacement   |
  | -------------------- | ----------------------- |
  | `List.foldl/3`       | `Enum.reduce/3`         |
  | `List.foldr/3`       | `Enum.reduce/3` (with `Enum.reverse/1`) |
  """

  use Credence.Rule
  alias Credence.Issue

  @flagged_fns [:foldl, :foldr]

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case extract_list_fold(node) do
          {:ok, fn_name, meta} ->
            issue = %Issue{
              rule: :no_list_fold,
              message: build_message(fn_name),
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
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      # Piped: source |> List.foldl(acc, fun) / List.foldr(acc, fun)
      {:|>, pipe_meta, [source, {{:., _, [mod, fn_name]}, call_meta, args}]} = node
      when fn_name in @flagged_fns and is_list(args) ->
        if list_module?(mod) do
          fix_piped_fold(fn_name, source, call_meta, args, pipe_meta)
        else
          node
        end

      # Direct 3-arg: List.foldl(list, acc, fun) / List.foldr(list, acc, fun)
      {{:., _, [mod, fn_name]}, meta, [_list, _acc, _fun] = args} = node
      when fn_name in @flagged_fns ->
        if list_module?(mod) do
          fix_direct_fold(fn_name, args, meta)
        else
          node
        end

      node ->
        node
    end)
    |> Sourceror.to_string()
  end

  # ── Fix helpers ────────────────────────────────────────────────────

  # foldl piped: source |> List.foldl(acc, fun) → source |> Enum.reduce(acc, fun)
  defp fix_piped_fold(:foldl, source, _call_meta, args, pipe_meta) do
    {:|>, pipe_meta, [source, enum_reduce_call(args)]}
  end

  # foldr piped: source |> List.foldr(acc, fun) → source |> Enum.reverse() |> Enum.reduce(acc, fun)
  defp fix_piped_fold(:foldr, source, _call_meta, args, pipe_meta) do
    reversed = {:|>, [], [source, enum_reverse_call()]}
    {:|>, pipe_meta, [reversed, enum_reduce_call(args)]}
  end

  # foldl direct: List.foldl(list, acc, fun) → Enum.reduce(list, acc, fun)
  defp fix_direct_fold(:foldl, args, _meta) do
    enum_reduce_call(args)
  end

  # foldr direct: List.foldr(list, acc, fun) → Enum.reduce(Enum.reverse(list), acc, fun)
  defp fix_direct_fold(:foldr, [list | rest_args], _meta) do
    reversed_list = {{:., [], [{:__aliases__, [], [:Enum]}, :reverse]}, [], [list]}
    enum_reduce_call([reversed_list | rest_args])
  end

  defp enum_reduce_call(args) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :reduce]}, [], args}
  end

  defp enum_reverse_call do
    {{:., [], [{:__aliases__, [], [:Enum]}, :reverse]}, [], []}
  end

  # ── Shared detection ───────────────────────────────────────────────

  defp extract_list_fold({{:., meta, [mod, fn_name]}, _, args})
       when fn_name in @flagged_fns and is_list(args) do
    if list_module?(mod), do: {:ok, fn_name, meta}, else: :error
  end

  defp extract_list_fold(_), do: :error

  defp list_module?({:__aliases__, _, [:List]}), do: true
  defp list_module?(_), do: false

  defp build_message(:foldl) do
    """
    `List.foldl/3` is not idiomatic Elixir.

    Use `Enum.reduce/3` instead — it is the standard way to
    fold over a collection:

        Enum.reduce(list, acc, fn elem, acc -> ... end)
    """
  end

  defp build_message(:foldr) do
    """
    `List.foldr/3` is not idiomatic Elixir.

    Use `Enum.reduce/3` instead. If right-fold order is needed,
    reverse the list first:

        list |> Enum.reverse() |> Enum.reduce(acc, fun)
    """
  end
end
