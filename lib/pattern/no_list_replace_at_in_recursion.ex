defmodule Credence.Pattern.NoListReplaceAtInRecursion do
  @moduledoc """
  Check-only rule: Flags `List.replace_at/3` or `List.update_at/3` with a
  dynamic (non-literal) index inside **recursive** functions.

  Elixir lists are linked lists — both `List.replace_at/3` and
  `List.update_at/3` rebuild the list up to the target index, making them O(n).
  Using them with a changing index on every recursive call makes the overall
  complexity O(n × iterations). Convert the list to a tuple up front and use
  `put_elem/3` for O(1) updates instead.

  This rule catches the general case: any non-literal offset used with
  `List.replace_at/3` or `List.update_at/3` inside a recursive function. It
  does NOT fire when the offset is a literal integer.

  ## Bad

      defp fill(list, idx, last_idx) when idx > last_idx, do: list
      defp fill(list, idx, last_idx) do
        list |> List.replace_at(idx, 9) |> fill(idx + 1, last_idx)
      end

      defp decrement(list, idx) do
        updated = List.update_at(list, idx, &(&1 - 1))
        decrement(updated, idx - 1)
      end

  ## Good

      defp fill(list, idx, last_idx) do
        tuple = List.to_tuple(list)
        do_fill(tuple, idx, last_idx) |> Tuple.to_list()
      end

      defp do_fill(tuple, idx, last_idx) when idx > last_idx, do: tuple
      defp do_fill(tuple, idx, last_idx) do
        put_elem(tuple, idx, 9) |> do_fill(idx + 1, last_idx)
      end

  ## Check-only (no auto-fix)

  The fix requires converting the list to a tuple in the calling function and
  threading the tuple through all recursive calls. This cannot be performed
  safely by an automated tool.
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    ast
    |> collect_function_defs()
    |> Enum.filter(fn {name, body} -> recursive?(body, name) end)
    |> Enum.flat_map(fn {_name, body} -> find_issues_in_body(body) end)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # -- collection ----------------------------------------------------------

  defp collect_function_defs(ast) do
    {_, fns} =
      Macro.prewalk(ast, [], fn
        {kind, _meta, [head, body_kw]} = node, acc
        when kind in [:def, :defp] and is_list(body_kw) ->
          name = extract_func_name(head)
          body = extract_do_body(body_kw)

          if name != nil and body != nil do
            {node, [{name, body} | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    fns
  end

  defp extract_func_name({:when, _, [{name, _, _} | _]}), do: name
  defp extract_func_name({name, _, _}) when is_atom(name), do: name
  defp extract_func_name(_), do: nil

  defp extract_do_body(body_kw) when is_list(body_kw) do
    Enum.find_value(body_kw, fn
      {{:__block__, _, [:do]}, body} -> body
      {:do, body} -> body
      _ -> nil
    end)
  end

  # -- recursion detection -------------------------------------------------

  defp recursive?(_, nil), do: true

  defp recursive?(body, func_name) do
    {_, found} =
      Macro.prewalk(body, false, fn
        {^func_name, _, args} = node, _ when is_list(args) -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  # -- issue detection -----------------------------------------------------

  defp find_issues_in_body(body) do
    {_, issues} =
      Macro.prewalk(body, [], fn
        # Direct: List.replace_at(list, index, val) — exactly 3 args
        {{:., _, [{:__aliases__, _, [:List]}, :replace_at]}, meta,
         [_list, index, _val]} = node,
        issues ->
          if flagged_index?(index) do
            {node, [trigger_issue(:replace_at, meta) | issues]}
          else
            {node, issues}
          end

        # Piped: list |> List.replace_at(index, val)
        {:|>, meta,
         [_list, {{:., _, [{:__aliases__, _, [:List]}, :replace_at]}, _, [index, _val]}]} =
            node,
        issues ->
          if flagged_index?(index) do
            {node, [trigger_issue(:replace_at, meta) | issues]}
          else
            {node, issues}
          end

        # Direct: List.update_at(list, index, fun) — exactly 3 args
        {{:., _, [{:__aliases__, _, [:List]}, :update_at]}, meta,
         [_list, index, _fun]} = node,
        issues ->
          if flagged_index?(index) do
            {node, [trigger_issue(:update_at, meta) | issues]}
          else
            {node, issues}
          end

        # Piped: list |> List.update_at(index, fun)
        {:|>, meta,
         [_list, {{:., _, [{:__aliases__, _, [:List]}, :update_at]}, _, [index, _fun]}]} =
            node,
        issues ->
          if flagged_index?(index) do
            {node, [trigger_issue(:update_at, meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp flagged_index?(index) do
    not literal_integer?(index)
  end

  defp literal_integer?(n) when is_integer(n), do: true
  defp literal_integer?({:__block__, _, [n]}) when is_integer(n), do: true
  defp literal_integer?(_), do: false

  defp trigger_issue(fun, meta) do
    label = if fun == :replace_at, do: "List.replace_at/3", else: "List.update_at/3"

    %Issue{
      rule: :no_list_replace_at_in_recursion,
      message:
        "Using `#{label}` with a dynamic index inside a recursive function is O(n) per call. " <>
          "Convert the list to a tuple with `List.to_tuple/1` " <>
          "and use `put_elem/3` for O(1) updates.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
