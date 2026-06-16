defmodule Credence.Pattern.NoListFoldl do
  @moduledoc """
  Detects `List.foldl/3` on a provably-list argument and suggests `Enum.reduce/3`.

  `List.foldl(list, acc, fun)` and `Enum.reduce(list, acc, fun)` fold a **list**
  identically — same left-to-right order, same `fun.(elem, acc)` argument order.
  `Enum.reduce/3` is the idiomatic Elixir fold; `List.foldl/3` usually signals
  code ported from Erlang.

  ## Safe core — provably-list argument only

  The two are **not** interchangeable on a non-list enumerable: `List.foldl`
  raises `FunctionClauseError` on a map/range/stream, whereas `Enum.reduce`
  succeeds — a value-vs-crash divergence. So the rule fires only when the folded
  argument is **provably a list**: a list literal, a `++`, or a (possibly piped)
  call to a list-returning function (`Enum.map/filter/…`, `Map.keys`,
  `String.split`, `List.*`, …). A bare variable is left alone — we can't prove
  it is a list, and an expression rewrite can't add an `is_list` guard.

  `List.foldr/3` is intentionally **not** covered: it is a *right* fold, needing
  `Enum.reduce(Enum.reverse(list), acc, fun)` — more verbose than `List.foldr`.

  ## Bad

      List.foldl([1, 2, 3], 0, fun)

      nums |> Enum.filter(&pos?/1) |> List.foldl(0, fun)

  ## Good

      Enum.reduce([1, 2, 3], 0, fun)

      nums |> Enum.filter(&pos?/1) |> Enum.reduce(0, fun)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  # Functions whose result is always a list (mirrors no_enum_count_for_length).
  @list_returning %{
    Enum: ~w(map filter reject to_list sort sort_by uniq uniq_by reverse take drop
         take_while drop_while flat_map with_index dedup dedup_by concat
         intersperse chunk_every chunk_by slice map_every scan)a,
    String: ~w(graphemes codepoints split to_charlist)a,
    Map: ~w(keys values to_list)a,
    Keyword: ~w(keys values to_list delete drop take merge put put_new)a,
    List: ~w(wrap flatten delete delete_at insert_at replace_at update_at duplicate)a,
    Tuple: ~w(to_list)a
  }

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case check_node(node) do
          {:ok, issue} -> {node, [issue | issues]}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      # Piped: source |> List.foldl(acc, fun) → source |> Enum.reduce(acc, fun)
      {:|>, pipe_meta, [source, {{:., _, [mod, :foldl]}, _, [_acc, _fun] = args}]} = node ->
        if list_module?(mod) and provably_list?(source) do
          {:|>, pipe_meta, [source, enum_reduce_call(args)]}
        else
          node
        end

      # Direct: List.foldl(list, acc, fun) → Enum.reduce(list, acc, fun)
      {{:., _, [mod, :foldl]}, _meta, [list, _acc, _fun] = args} = node ->
        if list_module?(mod) and provably_list?(list), do: enum_reduce_call(args), else: node

      node ->
        node
    end)
  end

  # Piped: source |> List.foldl(acc, fun) — the folded value is the pipe source.
  defp check_node({:|>, _, [source, {{:., meta, [mod, :foldl]}, _, [_acc, _fun]}]}) do
    if list_module?(mod) and provably_list?(source), do: {:ok, build_issue(meta)}, else: :error
  end

  # Direct: List.foldl(list, acc, fun).
  defp check_node({{:., meta, [mod, :foldl]}, _, [list, _acc, _fun]}) do
    if list_module?(mod) and provably_list?(list), do: {:ok, build_issue(meta)}, else: :error
  end

  defp check_node(_), do: :error

  defp enum_reduce_call(args) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :reduce]}, [], args}
  end

  defp list_module?({:__aliases__, _, [:List]}), do: true
  defp list_module?(_), do: false

  # The argument is known to be a list when it is a list literal, a `++`, a
  # list-returning call, or a pipe whose last step returns a list.
  defp provably_list?(list) when is_list(list), do: true
  # Sourceror wraps a list literal as {:__block__, meta, [[...]]}.
  defp provably_list?({:__block__, _, [inner]}), do: provably_list?(inner)
  defp provably_list?({:++, _, [_, _]}), do: true
  defp provably_list?({:|>, _, [_lhs, step]}), do: list_returning_call?(step)

  defp provably_list?({{:., _, [{:__aliases__, _, [_mod]}, _fun]}, _, _args} = call),
    do: list_returning_call?(call)

  defp provably_list?(_), do: false

  defp list_returning_call?({{:., _, [{:__aliases__, _, [mod]}, fun]}, _, _args}) do
    case Map.fetch(@list_returning, mod) do
      {:ok, funs} -> fun in funs
      :error -> false
    end
  end

  defp list_returning_call?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :no_list_foldl,
      message:
        "`List.foldl/3` on a list is non-idiomatic; use `Enum.reduce/3` instead. " <>
          "(Only flagged when the argument is provably a list — the two differ on non-list enumerables.)",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
