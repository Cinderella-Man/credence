defmodule Credence.Pattern.NoRepeatedLengthInRecursion do
  @moduledoc """
  Check-only rule: flags `length/1`, `Enum.count/1`, or `byte_size/1` called
  on a parameter inside a recursive function, where the parameter is passed
  unchanged in the recursive self-call.

  Since `length/1` is O(n), calling it on every recursive step when the list
  doesn't change is wasteful. `byte_size/1` is O(1) but is still redundant
  computation that clutters the recursion body. Precompute the size once and
  pass it as an additional parameter.

  ## Bad

      defp sliding_window(list, right, max_len) do
        if right >= length(list) do
          max_len
        else
          sliding_window(list, right + 1, max(max_len, right + 1))
        end
      end

      defp do_count(string, sub, index, count) do
        sub_len = byte_size(sub)
        string_len = byte_size(string)
        if index + sub_len > string_len do
          count
        else
          do_count(string, sub, index + 1, count + 1)
        end
      end

  ## Good

      defp sliding_window(list, len, right, max_len) do
        if right >= len do
          max_len
        else
          sliding_window(list, len, right + 1, max(max_len, right + 1))
        end
      end

      defp do_count(string, sub, sub_len, string_len, index, count) do
        if index + sub_len > string_len do
          count
        else
          do_count(string, sub, sub_len, string_len, index + 1, count + 1)
        end
      end

  ## Check-only

  The fix requires adding a parameter to the recursive function and threading
  it through all call sites — too invasive for auto-fix.
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
          param_names = extract_param_names(head)
          body = extract_do_body(body_kw)

          if func_name != nil and body != nil and param_names != [] do
            issues = find_length_in_recursion(body, func_name, param_names)
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

  defp find_length_in_recursion(body, func_name, param_names) do
    # Collect all self-calls and their argument lists
    recursive_calls = find_recursive_calls(body, func_name)

    if recursive_calls == [] do
      []
    else
      # Find all length(var) / Enum.count(var) calls in the body
      length_calls = find_length_calls(body)

      Enum.flat_map(length_calls, fn {fn_kind, called_var, meta} ->
        if called_var in param_names and
             param_unchanged_in_all_calls?(recursive_calls, param_names, called_var) do
          label = size_fn_label(fn_kind)
          [%Issue{
            rule: :no_repeated_length_in_recursion,
            message:
              "`#{label}(#{called_var})` is recomputed on every recursive step, " <>
                "but `#{called_var}` never changes. Precompute the size once " <>
                "and pass it as a parameter.",
            meta: %{line: Keyword.get(meta, :line)}
          }]
        else
          []
        end
      end)
    end
  end

  # Returns all argument lists of self-calls to `func_name` inside `body`.
  defp find_recursive_calls(body, func_name) do
    {_, calls} =
      Macro.prewalk(body, [], fn
        {^func_name, _, args} = node, acc when is_list(args) ->
          {node, [args | acc]}

        node, acc ->
          {node, acc}
      end)

    calls
  end

  # Finds `length(var)`, `Enum.count(var)`, and `byte_size(var)` calls,
  # returns [{fn_kind, var_name, meta}].
  defp find_length_calls(body) do
    {_, calls} =
      Macro.prewalk(body, [], fn
        # length(var)
        {:length, meta, [{var_name, _, ctx}]} = node, acc
        when is_atom(var_name) and is_atom(ctx) and var_name != :_ ->
          {node, [{:length, var_name, meta} | acc]}

        # byte_size(var)
        {:byte_size, meta, [{var_name, _, ctx}]} = node, acc
        when is_atom(var_name) and is_atom(ctx) and var_name != :_ ->
          {node, [{:byte_size, var_name, meta} | acc]}

        # Enum.count(var) — direct call
        {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, meta, [{var_name, _, ctx}]} = node,
        acc
        when is_atom(var_name) and is_atom(ctx) and var_name != :_ ->
          {node, [{:enum_count, var_name, meta} | acc]}

        # var |> Enum.count() — piped call
        {:|>, _, [{var_name, _, ctx}, {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, meta, _}]} =
            node,
        acc
        when is_atom(var_name) and is_atom(ctx) and var_name != :_ ->
          {node, [{:enum_count, var_name, meta} | acc]}

        node, acc ->
          {node, acc}
      end)

    calls
  end

  defp size_fn_label(:length), do: "length"
  defp size_fn_label(:byte_size), do: "byte_size"
  defp size_fn_label(:enum_count), do: "Enum.count"

  # Checks that `param_name` appears unchanged at the same position in every
  # recursive call. "Unchanged" means the argument is the same bare variable.
  defp param_unchanged_in_all_calls?(recursive_calls, param_names, param_name) do
    param_index = Enum.find_index(param_names, &(&1 == param_name))

    Enum.all?(recursive_calls, fn args ->
      case Enum.at(args, param_index) do
        {name, _, ctx} when is_atom(name) and is_atom(ctx) -> name == param_name
        _ -> false
      end
    end)
  end

  defp extract_func_name({:when, _, [{name, _, _} | _]}) when is_atom(name), do: name
  defp extract_func_name({name, _, _}) when is_atom(name), do: name
  defp extract_func_name(_), do: nil

  defp extract_param_names({:when, _, [head | _]}) do
    extract_param_names(head)
  end

  defp extract_param_names({_, _, args}) when is_list(args), do: extract_names_from_args(args)
  defp extract_param_names(_), do: []

  defp extract_names_from_args(args) do
    Enum.map(args, fn
      {name, _, ctx} when is_atom(name) and is_atom(ctx) -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_do_body(body_kw) when is_list(body_kw) do
    Enum.find_value(body_kw, fn
      {{:__block__, _, [:do]}, body} -> body
      _ -> nil
    end)
  end
end
