defmodule Credence.Pattern.NoListPopAtForAccess do
  @moduledoc """
  Detects `List.pop_at(list, 0) |> elem(n)` used to extract only the head
  (`n = 0`) or only the rest-after-head (`n = 1`) of a list, and rewrites
  it to the direct `List` accessor.

  `List.pop_at/2` returns a `{popped, rest}` tuple; using `elem/2` to pull
  out just one side allocates that tuple for nothing.

  ## Why `List.first` / `List.delete_at`, not `hd` / `tl`

  The obvious-looking rewrite — `hd/1` for `elem(0)` and `tl/1` for
  `elem(1)` — is **not** behaviour-preserving. `List.pop_at/2` tolerates an
  empty list (`List.pop_at([], 0)` is `{nil, []}`), so:

      List.pop_at([], 0) |> elem(0)  # => nil   but  hd([])  raises
      List.pop_at([], 0) |> elem(1)  # => []     but  tl([])  raises

  The accessors that match `pop_at`'s answer on *every* list — including the
  empty list — are `List.first/1` (defaults to `nil`) and `List.delete_at/2`
  (returns `[]` on an empty list). Both also raise the same
  `FunctionClauseError` as `List.pop_at/2` on non-list inputs, so the
  raise-on-non-list contract is preserved as well.

  ## Bad

      list |> List.pop_at(0) |> elem(0)
      list |> List.pop_at(0) |> elem(1)
      elem(List.pop_at(list, 0), 1)

  ## Good

      List.first(list)
      List.delete_at(list, 0)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case match_node(node) do
          {:ok, n, _list_expr, meta} -> {node, [build_issue(n, meta) | issues]}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn node ->
      case match_node(node) do
        {:ok, n, list_expr, _meta} -> rewrite(n, list_expr)
        :error -> node
      end
    end)
  end

  # --- matcher (shared by check and fix so they always agree) ---

  # Pipeline: ... |> List.pop_at(0) |> elem(n)
  defp match_node({:|>, _pipe_meta, [left, elem_node]}) do
    with true <- elem_call?(elem_node),
         n when n in [0, 1] <- elem_index(elem_node),
         # leftmost of the pipe chain must be List.pop_at(_, 0)
         pop_at_node <- rightmost_pipe(left),
         true <- pop_at_zero?(pop_at_node),
         {:ok, list_expr} <- pop_at_list(pop_at_node, left) do
      {:ok, n, list_expr, get_meta(elem_node)}
    else
      _ -> :error
    end
  end

  # Nested: elem(List.pop_at(x, 0), n)
  defp match_node({:elem, meta, [pop_at_node, n_arg]}) when is_list(meta) do
    with true <- pop_at_zero?(pop_at_node),
         n when n in [0, 1] <- unwrap_int(n_arg),
         {:ok, list_expr} <- pop_at_list(pop_at_node, nil) do
      {:ok, n, list_expr, meta}
    else
      _ -> :error
    end
  end

  defp match_node(_), do: :error

  # --- list-expression extraction ---

  # Piped form `|> List.pop_at(0)` (one explicit arg): the list is the value
  # piped into pop_at, i.e. the left of the inner pipe.
  defp pop_at_list(
         {{:., _, [{:__aliases__, _, [:List]}, :pop_at]}, _, [_idx]},
         {:|>, _, [list_expr, _right]}
       ),
       do: {:ok, list_expr}

  # Direct form `List.pop_at(list, 0)` (two explicit args): the list is the
  # first argument.
  defp pop_at_list(
         {{:., _, [{:__aliases__, _, [:List]}, :pop_at]}, _, [src, _idx]},
         _left
       ),
       do: {:ok, src}

  defp pop_at_list(_, _), do: :error

  # --- replacements ---

  # `... |> elem(0)` extracts the popped head -> List.first/1 (nil on []).
  defp rewrite(0, list_expr) do
    {{:., [], [{:__aliases__, [], [:List]}, :first]}, [], [list_expr]}
  end

  # `... |> elem(1)` extracts the rest -> List.delete_at(list, 0) ([] on []).
  defp rewrite(1, list_expr) do
    {{:., [], [{:__aliases__, [], [:List]}, :delete_at]}, [], [list_expr, 0]}
  end

  # --- helpers ---

  defp rightmost_pipe({:|>, _, [_, right]}), do: right
  defp rightmost_pipe(other), do: other

  defp elem_call?({:elem, _, _}), do: true
  defp elem_call?(_), do: false

  defp elem_index({:elem, _, [n_arg]}), do: unwrap_int(n_arg)
  defp elem_index(_), do: nil

  # piped form: |> List.pop_at(0) — one explicit arg (the index)
  defp pop_at_zero?({{:., _, [{:__aliases__, _, [:List]}, :pop_at]}, _, [idx]}),
    do: unwrap_int(idx) == 0

  # direct form: List.pop_at(x, 0) — two explicit args
  defp pop_at_zero?({{:., _, [{:__aliases__, _, [:List]}, :pop_at]}, _, [_src, idx]}),
    do: unwrap_int(idx) == 0

  defp pop_at_zero?(_), do: false

  defp unwrap_int({:__block__, _, [n]}) when is_integer(n), do: n
  defp unwrap_int(n) when is_integer(n), do: n
  defp unwrap_int(_), do: nil

  defp get_meta({:elem, meta, _}), do: meta

  defp build_issue(0, meta) do
    %Issue{
      rule: :no_list_pop_at_for_access,
      message:
        "`List.pop_at(list, 0) |> elem(0)` allocates a tuple just to read the head. " <>
          "Use `List.first(list)` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp build_issue(1, meta) do
    %Issue{
      rule: :no_list_pop_at_for_access,
      message:
        "`List.pop_at(list, 0) |> elem(1)` allocates a tuple just to read the rest. " <>
          "Use `List.delete_at(list, 0)` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
