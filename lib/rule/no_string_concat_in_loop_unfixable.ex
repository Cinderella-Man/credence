defmodule Credence.Rule.NoStringConcatInLoopComplex do
  @moduledoc """
  Performance rule: Detects string concatenation with `<>` inside complex
  looping constructs that cannot be safely auto-fixed.

  This rule detects `<>` inside:

    * `Enum.reduce_while` — the accumulated value drives the halting logic
    * `for` comprehensions with `reduce` — complex multi-generator syntax
    * Recursive functions — too varied to generalise
    * `Enum.reduce` with block bodies or non-empty initial accumulators

  Each `<>` concatenation copies the entire accumulated binary, making
  character-by-character string building O(n²). This is the string equivalent
  of `list ++ [element]`.

  ## Bad

      Enum.reduce_while(chars, "", fn char, prefix ->
        candidate = prefix <> char
        if valid?(candidate), do: {:cont, candidate}, else: {:halt, prefix}
      end)

      for char <- chars, reduce: "" do
        acc -> acc <> char
      end

      def build("", acc), do: acc
      def build(<<char::utf8, rest::binary>>, acc) do
        build(rest, acc <> <<char::utf8>>)
      end

  ## Good

      graphemes
      |> Enum.reduce([], fn char, acc -> [char | acc] end)
      |> Enum.reverse()
      |> IO.iodata_to_binary()

      Enum.join(graphemes)
  """

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: false

  @impl true
  def check(ast, _opts) do
    loop_issues = find_in_loops(ast)
    recursive_issues = find_in_recursive(ast)

    (loop_issues ++ recursive_issues)
    |> Enum.uniq_by(fn issue -> issue.meta.line end)
  end

  # ── Loop detection ──────────────────────────────────────────────────

  defp find_in_loops(ast) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Enum.reduce_while (3-arg direct call)
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce_while]}, _meta, [_, _, _]} = node, issues ->
          {node, find_concat(node, issues)}

        # Enum.reduce (3-arg direct call)
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _meta, [_, _, _] = args} = node, issues ->
          if simple_fixable_reduce?(args) do
            {node, issues}
          else
            {node, find_concat(node, issues)}
          end

        # Pipeline: ... |> Enum.reduce_while(...)
        {:|>, _,
         [
           _,
           {{:., _, [{:__aliases__, _, [:Enum]}, :reduce_while]}, _, _} = reduce_call
         ]} = node,
        issues ->
          {node, find_concat(reduce_call, issues)}

        # Pipeline: ... |> Enum.reduce("", fn ...) — skip if fixable
        {:|>, _,
         [
           _,
           {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, ["", lambda]} = reduce_call
         ]} = node,
        issues ->
          case extract_simple_concat(lambda) do
            {:ok, _, _} -> {node, issues}
            :error -> {node, find_concat(reduce_call, issues)}
          end

        # Pipeline: ... |> Enum.reduce(non_empty_acc, fn ...)
        {:|>, _,
         [
           _,
           {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, _} = reduce_call
         ]} = node,
        issues ->
          {node, find_concat(reduce_call, issues)}

        # for comprehension
        {:for, _meta, _args} = node, issues ->
          {node, find_concat(node, issues)}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  # ── Recursive-function detection ────────────────────────────────────

  defp find_in_recursive(ast) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {kind, _meta, [{:when, _, [{name, _, params}, _guard]}, body_kw]} = node, issues
        when kind in [:def, :defp] and is_atom(name) and is_list(params) ->
          body = extract_body(body_kw)
          {node, check_recursive_body(body, name, issues)}

        {kind, _meta, [{name, _, params}, body_kw]} = node, issues
        when kind in [:def, :defp] and is_atom(name) and is_list(params) ->
          body = extract_body(body_kw)
          {node, check_recursive_body(body, name, issues)}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  # ── Helpers shared between modules (duplicated intentionally) ───────

  defp simple_fixable_reduce?([_list, "", lambda]) do
    case extract_simple_concat(lambda) do
      {:ok, _, _} -> true
      :error -> false
    end
  end

  defp simple_fixable_reduce?(_), do: false

  defp extract_simple_concat(
         {:fn, _,
          [
            {:->, _,
             [
               [{_elem_ctx, _, _} = elem_var, {acc_name, _, _}],
               {:<>, _, [left, right]}
             ]}
          ]}
       ) do
    case left do
      {^acc_name, _, _} ->
        if references_var?(right, acc_name) do
          :error
        else
          {:ok, elem_var, right}
        end

      _ ->
        :error
    end
  end

  defp extract_simple_concat(_), do: :error

  defp references_var?(ast, name) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {^name, _, _} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found
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
      rule: :no_string_concat_in_loop_complex,
      message:
        "Avoid `<>` string concatenation inside loops — each concatenation " <>
          "copies the entire accumulated binary (O(n²)). Accumulate into an " <>
          "iodata list and call `IO.iodata_to_binary/1` at the end, or use " <>
          "`Enum.join/1`.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
