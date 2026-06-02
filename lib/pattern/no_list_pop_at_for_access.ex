defmodule Credence.Pattern.NoListPopAtForAccess do
  @moduledoc """
  Check-only rule: Detects `List.pop_at(list, 0) |> elem(n)` used to extract
  only the head (`n=0`) or the tail (`n=1`) of a list.

  `List.pop_at/2` returns a `{popped, rest}` tuple — using `elem/2` to
  extract just one of the two values allocates a tuple for nothing.
  Use `hd/1`, `tl/1`, or direct pattern matching instead.

  ## Bad

      list |> List.pop_at(0) |> elem(1)   # roundabout tl/1
      list |> List.pop_at(0) |> elem(0)   # roundabout hd/1
      elem(List.pop_at(list, 0), 1)        # same, nested form

  ## Good

      tl(list)
      hd(list)
      [_ | rest] = list
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipeline: ... |> List.pop_at(0) |> elem(n)
        {:|>, _pipe_meta, [left, elem_node]} = node, issues ->
          with true <- elem_call?(elem_node),
               n when n in [0, 1] <- elem_index(elem_node),
               # leftmost of the pipe chain must be List.pop_at(_, 0)
               pop_at_node <- rightmost_pipe(left),
               true <- pop_at_zero?(pop_at_node) do
            {node, [build_issue(n, get_meta(elem_node)) | issues]}
          else
            _ -> {node, issues}
          end

        # Nested: elem(List.pop_at(x, 0), n)
        {:elem, meta, [pop_at_node, n_arg]} = node, issues
        when is_list(meta) ->
          with true <- pop_at_zero?(pop_at_node),
               n when n in [0, 1] <- unwrap_int(n_arg) do
            {node, [build_issue(n, meta) | issues]}
          else
            _ -> {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

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
  defp get_meta(_), do: []

  defp build_issue(0, meta) do
    %Issue{
      rule: :no_list_pop_at_for_access,
      message:
        "`List.pop_at(list, 0) |> elem(0)` is a roundabout `hd/1`. " <>
          "Use `hd/1` or pattern-match with `[head | _]` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp build_issue(1, meta) do
    %Issue{
      rule: :no_list_pop_at_for_access,
      message:
        "`List.pop_at(list, 0) |> elem(1)` is a roundabout `tl/1`. " <>
          "Use `tl/1` or pattern-match with `[_ | tail]` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
