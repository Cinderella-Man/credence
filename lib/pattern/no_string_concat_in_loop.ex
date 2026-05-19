defmodule Credence.Pattern.NoStringConcatInLoop do
  @moduledoc """
  Performance rule: Detects string concatenation with `<>` inside
  `Enum.reduce` calls with an empty string initial accumulator that can
  be automatically fixed.

  Each `<>` concatenation copies the entire accumulated binary, making
  character-by-character string building O(n²). This is the string equivalent
  of `list ++ [element]`.

  The following patterns are automatically fixed:

    * `Enum.reduce(list, "", fn elem, acc -> acc <> elem end)` → `Enum.join(list)`
    * `Enum.reduce(list, "", fn elem, acc -> acc <> expr end)` where `expr`
      doesn't reference `acc` → `Enum.map_join(list, fn elem -> expr end)`

  ## Bad

      Enum.reduce(graphemes, "", fn char, acc ->
        acc <> char
      end)

      Enum.reduce(graphemes, "", fn char, acc ->
        acc <> String.upcase(char)
      end)

  ## Good

      Enum.join(graphemes)

      Enum.map_join(graphemes, fn char -> String.upcase(char) end)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Direct call: Enum.reduce(list, "", fn elem, acc -> acc <> expr end)
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [_list, init, lambda]} = node,
        issues ->
          if empty_string_literal?(init) and match?({:ok, _, _}, extract_simple_concat(lambda)),
            do: {node, [build_issue(meta) | issues]},
            else: {node, issues}

        # Pipeline: ... |> Enum.reduce("", fn elem, acc -> acc <> expr end)
        {:|>, _,
         [
           _,
           {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [init, lambda]}
         ]} = node,
        issues ->
          if empty_string_literal?(init) and match?({:ok, _, _}, extract_simple_concat(lambda)),
            do: {node, [build_issue(meta) | issues]},
            else: {node, issues}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, &maybe_rewrite/1)
  end

  # Direct call: Enum.reduce(list, "", fn elem, acc -> acc <> expr end)
  defp maybe_rewrite(
         {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [list, init, lambda]} = node
       ) do
    with true <- empty_string_literal?(init),
         {:ok, elem_var, expr} <- extract_simple_concat(lambda) do
      if simple_identity?(elem_var, expr) do
        enum_join_call(list)
      else
        enum_map_join_call(list, elem_var, expr)
      end
    else
      _ -> node
    end
  end

  # Pipe form: lhs |> Enum.reduce("", fn elem, acc -> acc <> expr end)
  defp maybe_rewrite(
         {:|>, pipe_meta,
          [
            lhs,
            {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [init, lambda]}
          ]} = node
       ) do
    with true <- empty_string_literal?(init),
         {:ok, elem_var, expr} <- extract_simple_concat(lambda) do
      replacement =
        if simple_identity?(elem_var, expr) do
          enum_join_pipe_call()
        else
          enum_map_join_pipe_call(elem_var, expr)
        end

      {:|>, pipe_meta, [lhs, replacement]}
    else
      _ -> node
    end
  end

  defp maybe_rewrite(node), do: node

  defp empty_string_literal?(""), do: true
  defp empty_string_literal?({:__block__, _, [""]}), do: true
  defp empty_string_literal?(_), do: false

  # `acc <> elem` — RHS of <> is exactly the elem var, so `Enum.join` suffices.
  defp simple_identity?({elem_name, _, ctx1}, {right_name, _, ctx2})
       when is_atom(elem_name) and is_atom(right_name) and
              (is_nil(ctx1) or is_atom(ctx1)) and (is_nil(ctx2) or is_atom(ctx2)) do
    elem_name == right_name
  end

  defp simple_identity?(_, _), do: false

  defp enum_join_call(list) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :join]}, [], [list]}
  end

  defp enum_join_pipe_call do
    {{:., [], [{:__aliases__, [], [:Enum]}, :join]}, [], []}
  end

  defp enum_map_join_call(list, elem_var, expr) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :map_join]}, [], [list, build_lambda(elem_var, expr)]}
  end

  defp enum_map_join_pipe_call(elem_var, expr) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :map_join]}, [], [build_lambda(elem_var, expr)]}
  end

  defp build_lambda(elem_var, body) do
    {:fn, [], [{:->, [], [[elem_var], body]}]}
  end

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

  defp build_issue(meta) do
    %Issue{
      rule: :no_string_concat_in_loop,
      message:
        "Avoid `<>` string concatenation inside `Enum.reduce` with an empty " <>
          "string accumulator — each concatenation copies the entire accumulated " <>
          "binary (O(n²)). Use `Enum.join/1` or `Enum.map_join/2` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
