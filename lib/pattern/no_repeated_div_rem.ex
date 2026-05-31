defmodule Credence.Pattern.NoRepeatedDivRem do
  @moduledoc """
  Check-only rule: flags `div/2` or `rem/2` called with the same arguments
  more than once in the same function clause body.

  Since `div/2` and `rem/2` are pure, side-effect-free operations, the result
  should be computed once and bound to a variable.

  ## Bad

      defp loop(number, count) do
        new_count = count + div(number, 5)
        loop(div(number, 5), new_count)
      end

  ## Good

      defp loop(number, count) do
        quotient = div(number, 5)
        loop(quotient, count + quotient)
      end

  ## Check-only

  The fix requires choosing a variable name and restructuring expressions —
  too subjective for auto-fix.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {kind, _meta, [head, body_kw]} = node, acc
        when kind in [:def, :defp] and is_list(body_kw) ->
          func_name = extract_func_name(head)
          body = extract_do_body(body_kw)

          if func_name != nil and body != nil do
            issues = find_repeated_calls(body)
            {node, issues ++ acc}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  defp find_repeated_calls(body) do
    calls = collect_div_rem_calls(body)

    grouped =
      Enum.group_by(calls, fn {name, args_str, _meta} ->
        {name, args_str}
      end)

    Enum.flat_map(grouped, fn
      {{name, args_str}, occurrences} when length(occurrences) >= 2 ->
        {_, _, meta} = hd(occurrences)

        [
          %Issue{
            rule: :no_repeated_div_rem,
            message:
              "`#{name}(#{args_str})` is computed multiple times in the same scope. " <>
                "Bind the result to a variable and reuse it.",
            meta: %{line: Keyword.get(meta, :line)}
          }
        ]

      _ ->
        []
    end)
  end

  defp collect_div_rem_calls(body) do
    {_ast, calls} =
      Macro.prewalk(body, [], fn
        {:div, meta, [_, _] = args} = node, acc ->
          args_str = Enum.map_join(args, ", ", &Macro.to_string/1)
          {node, [{:div, args_str, meta} | acc]}

        {:rem, meta, [_, _] = args} = node, acc ->
          args_str = Enum.map_join(args, ", ", &Macro.to_string/1)
          {node, [{:rem, args_str, meta} | acc]}

        node, acc ->
          {node, acc}
      end)

    calls
  end

  defp extract_func_name({:when, _, [{name, _, _} | _]}) when is_atom(name), do: name
  defp extract_func_name({name, _, _}) when is_atom(name), do: name
  defp extract_func_name(_), do: nil

  defp extract_do_body(body_kw) when is_list(body_kw) do
    Enum.find_value(body_kw, fn
      {{:__block__, _, [:do]}, body} -> body
      _ -> nil
    end)
  end
end
