defmodule Credence.Rule.NoEnumAtMidpointAccess do
  @moduledoc """
  Performance rule: Flags `Enum.at/2` with a midpoint index inside
  **non-recursive** functions.

  Elixir lists are linked lists. `Enum.at/2` is an O(n) operation. When the
  index is derived from midpoint arithmetic (e.g. `div(low + high, 2)`), the
  code almost certainly wants O(1) random access. Converting the list to a
  tuple with `List.to_tuple/1` and using `elem/2` achieves this.

  ## Auto-fixable

  The fix inserts a `List.to_tuple/1` call at the top of the enclosing
  function body and replaces every flagged `Enum.at/2` call with `elem/2`.

  ### Pattern: direct call with midpoint variable

      # Before
      def find(list, low, high) do
        mid = low + div(high - low, 2)
        Enum.at(list, mid)
      end

      # After
      def find(list, low, high) do
        list_tuple = List.to_tuple(list)
        mid = low + div(high - low, 2)
        elem(list_tuple, mid)
      end

  ### Pattern: piped call

      # Before
      def find(list, low, high) do
        mid = div(low + high, 2)
        list |> Enum.at(mid)
      end

      # After
      def find(list, low, high) do
        list_tuple = List.to_tuple(list)
        mid = div(low + high, 2)
        elem(list_tuple, mid)
      end

  ### Pattern: inline midpoint expression

      # Before
      def find(list, low, high) do
        Enum.at(list, div(low + high, 2))
      end

      # After
      def find(list, low, high) do
        list_tuple = List.to_tuple(list)
        elem(list_tuple, div(low + high, 2))
      end

  ### Pattern: multiple lists

      # Before
      def compare(keys, values, low, high) do
        mid = low + div(high - low, 2)
        k = Enum.at(keys, mid)
        v = Enum.at(values, mid)
        {k, v}
      end

      # After
      def compare(keys, values, low, high) do
        keys_tuple = List.to_tuple(keys)
        values_tuple = List.to_tuple(values)
        mid = low + div(high - low, 2)
        k = elem(keys_tuple, mid)
        v = elem(values_tuple, mid)
        {k, v}
      end

  ### Pattern: inside anonymous function (e.g. Enum.reduce_while)

      # Before
      def search(list, target) do
        Enum.reduce_while(0..100, {0, length(list) - 1}, fn _, {low, high} ->
          mid = low + div(high - low, 2)
          mid_val = Enum.at(list, mid)
          ...
        end)
      end

      # After — conversion at top of enclosing def, NOT inside the fn
      def search(list, target) do
        list_tuple = List.to_tuple(list)
        Enum.reduce_while(0..100, {0, length(list) - 1}, fn _, {low, high} ->
          mid = low + div(high - low, 2)
          mid_val = elem(list_tuple, mid)
          ...
        end)
      end

  See also `Credence.Rule.NoEnumAtBinarySearch` which catches the same
  anti-pattern in recursive functions (not auto-fixable).
  """
  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    ast
    |> collect_function_defs()
    |> Enum.reject(fn {name, body} -> recursive?(body, name) end)
    |> Enum.flat_map(fn {_name, body} -> find_issues_in_body(body) end)
  end

  @impl true
  def fix(source, _opts) do
    Sourceror.parse_string!(source)
    |> Macro.postwalk(fn
      {kind, _, _} = node when kind in [:def, :defp] -> maybe_fix_function(node)
      node -> node
    end)
    |> Sourceror.to_string()
  end

  defp maybe_fix_function({kind, meta, [head, body_kw]} = node) when is_list(body_kw) do
    func_name = extract_func_name(head)
    body = extract_do_body(body_kw)

    with body when body != nil <- body,
         list_vars when list_vars != [] <- collect_flagged_list_vars(body),
         false <- recursive?(body, func_name) do
      var_map = Map.new(list_vars, fn var -> {var, :"#{var}_tuple"} end)

      new_body =
        body
        |> insert_conversions(var_map)
        |> replace_enum_at(var_map)

      {kind, meta, [head, put_do_body(body_kw, new_body)]}
    else
      _ -> node
    end
  end

  defp maybe_fix_function(node), do: node

  # Collect list variable names that appear as the first arg to flagged Enum.at.
  defp collect_flagged_list_vars(body) do
    {_, {vars, _mids}} =
      Macro.prewalk(body, {MapSet.new(), MapSet.new()}, fn
        {:=, _, [{var, _, _}, expr]} = node, {vars, mids} when is_atom(var) ->
          mids = if midpoint_expr?(expr), do: MapSet.put(mids, var), else: mids
          {node, {vars, mids}}

        # Direct: Enum.at(list_var, index)
        {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [{list_var, _, _}, index]} = node,
        {vars, mids}
        when is_atom(list_var) ->
          vars = if flagged_index?(index, mids), do: MapSet.put(vars, list_var), else: vars
          {node, {vars, mids}}

        # Piped: list_var |> Enum.at(index)
        {:|>, _, [{list_var, _, _}, {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [index]}]} =
            node,
        {vars, mids}
        when is_atom(list_var) ->
          vars = if flagged_index?(index, mids), do: MapSet.put(vars, list_var), else: vars
          {node, {vars, mids}}

        node, acc ->
          {node, acc}
      end)

    MapSet.to_list(vars)
  end

  # Prepend `<var>_tuple = List.to_tuple(<var>)` at the top of the body.
  defp insert_conversions(body, var_map) do
    assignments =
      var_map
      |> Enum.sort()
      |> Enum.map(fn {list_var, tuple_var} ->
        {:=, [], [{tuple_var, [], nil}, list_to_tuple_call({list_var, [], nil})]}
      end)

    case body do
      {:__block__, meta, stmts} -> {:__block__, meta, assignments ++ stmts}
      single_expr -> {:__block__, [], assignments ++ [single_expr]}
    end
  end

  # Replace Enum.at(list_var, index) → elem(tuple_var, index) for matched vars.
  defp replace_enum_at(body, var_map) do
    Macro.postwalk(body, fn
      # Direct: Enum.at(list_var, index) → elem(tuple_var, index)
      {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [{list_var, _, _}, index]} = node
      when is_atom(list_var) ->
        case Map.fetch(var_map, list_var) do
          {:ok, tuple_var} -> {:elem, [], [{tuple_var, [], nil}, index]}
          :error -> node
        end

      # Piped: list_var |> Enum.at(index) → elem(tuple_var, index)
      {:|>, _, [{list_var, _, _}, {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [index]}]} =
          node
      when is_atom(list_var) ->
        case Map.fetch(var_map, list_var) do
          {:ok, tuple_var} -> {:elem, [], [{tuple_var, [], nil}, index]}
          :error -> node
        end

      node ->
        node
    end)
  end

  defp list_to_tuple_call(arg) do
    {{:., [], [{:__aliases__, [], [:List]}, :to_tuple]}, [], [arg]}
  end

  defp put_do_body(body_kw, new_body) when is_list(body_kw) do
    Enum.map(body_kw, fn
      {{:__block__, _, [:do]} = key, _old} -> {key, new_body}
      {:do, _old} -> {:do, new_body}
      other -> other
    end)
  end

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

  defp find_issues_in_body(body) do
    {_, {issues, _mids}} =
      Macro.prewalk(body, {[], MapSet.new()}, fn
        {:=, _, [{var, _, _}, expr]} = node, {issues, mids} when is_atom(var) ->
          mids = if midpoint_expr?(expr), do: MapSet.put(mids, var), else: mids
          {node, {issues, mids}}

        # Direct: Enum.at(list, mid)
        {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, meta, [_list, index]} = node, {issues, mids} ->
          if flagged_index?(index, mids) do
            {node, {[trigger_issue(meta) | issues], mids}}
          else
            {node, {issues, mids}}
          end

        # Piped: list |> Enum.at(mid)
        {:|>, meta, [_list, {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [index]}]} = node,
        {issues, mids} ->
          if flagged_index?(index, mids) do
            {node, {[trigger_issue(meta) | issues], mids}}
          else
            {node, {issues, mids}}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  defp extract_do_body(body_kw) when is_list(body_kw) do
    Enum.find_value(body_kw, fn
      {{:__block__, _, [:do]}, body} -> body
      {:do, body} -> body
      _ -> nil
    end)
  end

  defp extract_func_name({:when, _, [{name, _, _} | _]}), do: name
  defp extract_func_name({name, _, _}) when is_atom(name), do: name
  defp extract_func_name(_), do: nil

  defp recursive?(_, nil), do: true

  defp recursive?(body, func_name) do
    {_, found} =
      Macro.prewalk(body, false, fn
        {^func_name, _, args} = node, _ when is_list(args) -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  defp flagged_index?(index, mids) do
    mid_var?(index, mids) or midpoint_expr?(index)
  end

  defp mid_var?({var, _, _}, mids) when is_atom(var), do: MapSet.member?(mids, var)
  defp mid_var?(_, _), do: false

  defp unwrap_literal({:__block__, _, [val]}), do: val
  defp unwrap_literal(val), do: val

  defp midpoint_expr?({:+, _, [_low, {:div, _, [{:-, _, [_, _]}, d]}]}),
    do: unwrap_literal(d) == 2

  defp midpoint_expr?({:div, _, [{:+, _, [_, _]}, d]}),
    do: unwrap_literal(d) == 2

  defp midpoint_expr?({:+, _, [{:div, _, [{:-, _, [_, _]}, d]}, _]}),
    do: unwrap_literal(d) == 2

  defp midpoint_expr?(_), do: false

  defp trigger_issue(meta) do
    %Issue{
      rule: :no_enum_at_midpoint_access,
      message:
        "Using `Enum.at/2` with a midpoint index on a list is O(n). " <>
          "Convert the list to a tuple with `List.to_tuple/1` and use " <>
          "`elem/2` for O(1) access.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
