defmodule Credence.Pattern.NoEnumAtInLoop do
  @moduledoc """
  Performance rule: Detects `Enum.at/2` inside looping constructs
  (`Enum.reduce`, `Enum.map`, `Enum.each`, `Enum.filter`, `Enum.flat_map`,
  `for` comprehensions) or recursive functions.

  `Enum.at/2` is O(n) on linked lists because it traverses from the head to
  the given index. Inside a loop this compounds to O(n²) or worse. This is
  one of the most common performance traps for developers coming from
  languages with array-based lists.

  This rule is **not auto-fixable** because every remedy requires non-local
  changes: inserting `List.to_tuple/1` in an outer scope, restructuring a
  callback signature for `Enum.with_index/1`, or rewriting the algorithm to
  use pattern matching. These transformations depend on surrounding context
  and cannot be expressed as a mechanical AST node swap.

  ## Bad

      defp expand(graphemes, left, right, count) do
        if Enum.at(graphemes, left) == Enum.at(graphemes, right) do
          expand(graphemes, left - 1, right + 1, count)
        else
          0
        end
      end

      Enum.reduce(0..n, 0, fn i, acc ->
        acc + Enum.at(list, i)
      end)

  ## Good

      # Option 1: Convert to tuple for O(1) indexed access
      tuple = List.to_tuple(graphemes)
      elem(tuple, left) == elem(tuple, right)

      # Option 2: Use pattern matching / recursion on the list directly
      defp process([head | tail]), do: ...

      # Option 3: Use Enum.with_index or Enum.zip to pair values with indices
      Enum.reduce(Enum.with_index(list), 0, fn {val, _idx}, acc -> acc + val end)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @enum_loops [:reduce, :reduce_while, :map, :flat_map, :each, :filter]

  @impl true
  def fixable?, do: false

  @impl true
  def check(ast, _opts) do
    loop_issues = find_in_loops(ast)
    recursive_issues = find_in_recursive(ast)

    (loop_issues ++ recursive_issues)
    |> Enum.uniq_by(fn issue -> issue.meta.line end)
  end

  defp find_in_loops(ast) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # for comprehension
        {:for, _meta, _args} = node, issues ->
          {node, find_enum_at(node, issues)}

        # Enum.reduce / map / flat_map / each / filter / reduce_while
        {{:., _, [{:__aliases__, _, [:Enum]}, func]}, _meta, args} = node, issues
        when func in @enum_loops and is_list(args) ->
          {node, find_enum_at(node, issues)}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp find_in_recursive(ast) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # IMPORTANT: guarded pattern must come first — otherwise the unguarded
        # pattern matches with name=:when (since {:when, meta, [call, guard]}
        # satisfies {name, _, _params} where name is an atom).
        {kind, _meta, [{:when, _, [{name, _, _params}, _guard]}, body_kw]} = node, issues
        when kind in [:def, :defp] and is_atom(name) ->
          body = extract_body(body_kw)
          {node, check_recursive_body(body, name, issues)}

        {kind, _meta, [{name, _, _params}, body_kw]} = node, issues
        when kind in [:def, :defp] and is_atom(name) ->
          body = extract_body(body_kw)
          {node, check_recursive_body(body, name, issues)}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp check_recursive_body(nil, _name, acc), do: acc

  defp check_recursive_body(body, name, acc) do
    if body_calls_self?(body, name) do
      find_enum_at(body, acc)
    else
      acc
    end
  end

  defp body_calls_self?(body, name) do
    {_ast, found} =
      Macro.prewalk(body, false, fn
        {^name, _, args} = n, _acc when is_list(args) -> {n, true}
        n, a -> {n, a}
      end)

    found
  end

  defp find_enum_at(scope_ast, acc) do
    {_ast, issues} =
      Macro.prewalk(scope_ast, acc, fn
        {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, meta, _} = node, issues ->
          {node, [build_issue(meta) | issues]}

        node, issues ->
          {node, issues}
      end)

    issues
  end

  defp extract_body(body_kw) when is_list(body_kw), do: Keyword.get(body_kw, :do)
  defp extract_body(body), do: body

  defp build_issue(meta) do
    %Issue{
      rule: :no_enum_at_in_loop,
      message:
        "Avoid `Enum.at/2` inside loops or recursive functions — it traverses the linked list " <>
          "to the index (O(n)) on every call, creating O(n²) cost. Use pattern matching, " <>
          "`Enum.with_index/1`, or convert to a tuple with `List.to_tuple/1` for indexed access.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
