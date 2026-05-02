defmodule Credence.Rule.NoStringConcatInLoop do
  @moduledoc """
  Performance rule: Detects string concatenation with `<>` inside looping
  constructs (`Enum.reduce`, `Enum.reduce_while`, `for` comprehensions) or
  recursive functions.

  Each `<>` concatenation copies the entire accumulated binary, making
  character-by-character string building O(n²). This is the string equivalent
  of `list ++ [element]`.

  ## Bad

      Enum.reduce(graphemes, "", fn char, acc ->
        acc <> char
      end)

      Enum.reduce_while(chars, "", fn char, prefix ->
        candidate = prefix <> char
        ...
      end)

  ## Good

      graphemes
      |> Enum.reduce([], fn char, acc -> [char | acc] end)
      |> Enum.reverse()
      |> IO.iodata_to_binary()

      # Or simply:
      Enum.join(graphemes)
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @enum_loops [:reduce, :reduce_while]

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
        # Enum.reduce / Enum.reduce_while
        {{:., _, [{:__aliases__, _, [:Enum]}, func]}, _meta, args} = node, issues
        when func in @enum_loops and is_list(args) ->
          {node, find_concat(node, issues)}

        # for comprehension
        {:for, _meta, _args} = node, issues ->
          {node, find_concat(node, issues)}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp find_in_recursive(ast) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
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
      find_concat(body, acc)
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

  defp find_concat(scope_ast, acc) do
    {_ast, issues} =
      Macro.prewalk(scope_ast, acc, fn
        {:<>, meta, _args} = node, issues ->
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
      rule: :no_string_concat_in_loop,
      message:
        "Avoid `<>` string concatenation inside loops — each concatenation copies the " <>
          "entire accumulated binary (O(n²)). Accumulate into an iodata list and call " <>
          "`IO.iodata_to_binary/1` at the end, or use `Enum.join/1`.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
