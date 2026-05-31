defmodule Credence.Pattern.NoListAsOptionalValue do
  @moduledoc """
  Detects when a list is used as an optional/maybe container, with `List.last/1`
  used to unwrap the single value.

  Using `[]` for "nothing" and `[x]` for "something" is an anti-pattern.
  Use `nil` as the "nothing" sentinel and pass the scalar directly.

  ## Bad

      defp loop([], acc, []), do: acc
      defp loop([x | rest], acc, wrapped) do
        val = List.last(wrapped)
        loop(rest, acc + val, [x])
      end

  ## Good

      defp loop([], acc, nil), do: acc
      defp loop([x | rest], acc, val) do
        loop(rest, acc + val, x)
      end
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    clauses = collect_clauses(ast)

    clauses
    |> Enum.group_by(fn {name, arity, _, _, _, _} -> {name, arity} end)
    |> Enum.flat_map(fn {_key, group} -> analyze_group(group) end)
    |> Enum.sort_by(fn issue -> issue.meta[:line] || 0 end)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # --- clause collection ---

  defp collect_clauses(ast) do
    {_ast, clauses} =
      Macro.prewalk(ast, [], fn node, acc ->
        case extract_clause(node) do
          {:ok, clause} -> {node, [clause | acc]}
          :error -> {node, acc}
        end
      end)

    Enum.reverse(clauses)
  end

  defp extract_clause({def_type, meta, [{fn_name, _, params}, body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(params) do
    {:ok, {fn_name, length(params), def_type, meta, params, body}}
  end

  defp extract_clause({def_type, _meta, [{:when, _, _}, _body]})
       when def_type in [:def, :defp] do
    :error
  end

  defp extract_clause(_), do: :error

  # --- analysis ---

  defp analyze_group(clauses) when length(clauses) < 2, do: []

  defp analyze_group(clauses) do
    arity = elem(hd(clauses), 1)

    Enum.flat_map(0..(arity - 1), fn param_idx ->
      check_param_as_optional(clauses, param_idx)
    end)
  end

  defp check_param_as_optional(clauses, param_idx) do
    # Find a clause where this param is []
    empty_clause =
      Enum.find(clauses, fn {_, _, _, _, params, _} ->
        empty_list_pattern?(Enum.at(params, param_idx))
      end)

    case empty_clause do
      nil ->
        []

      _ ->
        # Check other clauses for List.last on this param
        Enum.flat_map(clauses, fn {name, _, _, meta, params, body} ->
          param = Enum.at(params, param_idx)

          if variable_pattern?(param) do
            var_name = elem(param, 0)

            if calls_list_last_on_var?(body, var_name) and
                 recursive_calls_wrap_singleton?(body, name, param_idx) do
              [build_issue(name, meta)]
            else
              []
            end
          else
            []
          end
        end)
    end
  end

  # --- pattern helpers ---

  defp empty_list_pattern?({:__block__, _, [[]]}), do: true
  defp empty_list_pattern?([]), do: true
  defp empty_list_pattern?(_), do: false

  defp variable_pattern?({var, _, ctx}) when is_atom(var) and is_atom(ctx), do: true
  defp variable_pattern?(_), do: false

  # --- body analysis ---

  defp calls_list_last_on_var?(body, var_name) do
    {_, found} =
      Macro.prewalk(body, false, fn
        {{:., _, [{:__aliases__, _, [:List]}, :last]}, _, [{^var_name, _, _}]} = node, _acc ->
          {node, true}

        {:|>, _, [{^var_name, _, _}, {{:., _, [{:__aliases__, _, [:List]}, :last]}, _, _}]} =
            node,
            _acc ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp recursive_calls_wrap_singleton?(body, fn_name, param_idx) do
    calls = find_recursive_calls(body, fn_name)

    length(calls) > 0 and
      Enum.all?(calls, fn args ->
        arg = Enum.at(args, param_idx)
        singleton_list?(arg)
      end)
  end

  defp find_recursive_calls(body, fn_name) do
    {_ast, calls} =
      Macro.prewalk(body, [], fn
        {^fn_name, _, args} = node, acc when is_list(args) ->
          {node, [args | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(calls)
  end

  defp singleton_list?({:__block__, _, [inner]}) when is_list(inner), do: length(inner) == 1
  defp singleton_list?([_single]), do: true
  defp singleton_list?(_), do: false

  # --- issue ---

  defp build_issue(fn_name, meta) do
    %Issue{
      rule: :no_list_as_optional_value,
      message:
        "`#{fn_name}` uses a list as an optional container " <>
          "(`[]` for nothing, `[x]` for something) and unwraps with `List.last/1`. " <>
          "Use `nil` as the sentinel and pass the scalar directly.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
