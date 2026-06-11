defmodule Credence.Pattern.PreferPrependInAccumulator do
  @moduledoc """
  Performance rule: Detects `List.last(acc)` combined with `acc ++ [expr]` in
  a recursive accumulator function where `Enum.reverse(acc)` is used to
  produce the output. The `List.last/1` call is O(n) and the `acc ++ [expr]`
  append is also O(n), compounding to O(n²) overall.

  The auto-fix pattern-matches the accumulator head with `[head | _] = acc`
  (replacing `List.last/1`), rewrites `acc ++ [expr]` to `[expr | acc]`, and
  removes the now-unnecessary `Enum.reverse/1` calls (since prepend builds the
  list in the correct output order).

  ## Bad

      def build_groups(acc, []) do
        [Enum.reverse(acc)]
      end

      def build_groups(acc, [next | rest]) do
        last = List.last(acc)

        if next == last + 1 do
          build_groups(acc ++ [next], rest)
        else
          [Enum.reverse(acc) | build_groups([next], rest)]
        end
      end

  ## Good

      def build_groups(acc, []) do
        [acc]
      end

      def build_groups([head | _] = acc, [next | rest]) do
        if next == head + 1 do
          build_groups([next | acc], rest)
        else
          [acc | build_groups([next], rest)]
        end
      end
  """
  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {kind, meta, [{name, _, params}, body_kw]} = node, issues
        when kind in [:def, :defp] and is_atom(name) and is_list(params) ->
          body = extract_do_body(body_kw)
          {node, check_clause(body, name, params, meta, issues)}

        {kind, meta, [{:when, _, [{name, _, params}, _guard]}, body_kw]} = node, issues
        when kind in [:def, :defp] and is_atom(name) and is_list(params) ->
          body = extract_do_body(body_kw)
          {node, check_clause(body, name, params, meta, issues)}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    # Collect all fixable function names (those that have List.last + ++ + Enum.reverse)
    fixable = find_fixable_functions(ast)

    if map_size(fixable) == 0 do
      []
    else
      RuleHelpers.patches_from_postwalk(ast, &apply_fix(&1, fixable))
    end
  end

  # --- Check helpers ---

  defp check_clause(nil, _name, _params, _meta, issues), do: issues

  defp check_clause(body, _name, params, meta, issues) do
    Enum.reduce(params, issues, fn param, acc ->
      case param do
        {var_name, _, ctx} when is_atom(var_name) and (is_nil(ctx) or is_atom(ctx)) ->
          if uses_list_last?(body, var_name) and uses_append?(body, var_name) and
               uses_reverse?(body, var_name) do
            line = find_list_last_line(body, var_name) || Keyword.get(meta, :line)
            [build_issue(line) | acc]
          else
            acc
          end

        _ ->
          acc
      end
    end)
  end

  defp uses_list_last?(body, var_name) do
    {_ast, found} =
      Macro.prewalk(body, false, fn
        {{:., _, [{:__aliases__, _, [:List]}, :last]}, _, [{^var_name, _, _}]} = node, _ ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp uses_append?(body, var_name) do
    {_ast, found} =
      Macro.prewalk(body, false, fn
        {:++, _, [{^var_name, _, _}, _]} = node, _ -> {node, true}
        {:++, _, [_, {^var_name, _, _}]} = node, _ -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  defp uses_reverse?(body, var_name) do
    {_ast, found} =
      Macro.prewalk(body, false, fn
        {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, [{^var_name, _, _}]} = node, _ ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp find_list_last_line(body, var_name) do
    {_ast, line} =
      Macro.prewalk(body, nil, fn
        {{:., meta, [{:__aliases__, _, [:List]}, :last]}, _, [{^var_name, _, _}]} = node, _ ->
          {node, Keyword.get(meta, :line)}

        node, acc ->
          {node, acc}
      end)

    line
  end

  # --- Fix helpers: pass 1 — find fixable functions ---

  defp find_fixable_functions(ast) do
    {_ast, fixable} =
      Macro.prewalk(ast, %{}, fn
        {kind, _, [{name, _, params}, body_kw]} = node, acc
        when kind in [:def, :defp] and is_atom(name) and is_list(params) ->
          body = extract_do_body(body_kw)
          {node, check_fixable(acc, name, params, body)}

        {kind, _, [{:when, _, [{name, _, params}, _guard]}, body_kw]} = node, acc
        when kind in [:def, :defp] and is_atom(name) and is_list(params) ->
          body = extract_do_body(body_kw)
          {node, check_fixable(acc, name, params, body)}

        node, acc ->
          {node, acc}
      end)

    fixable
  end

  defp check_fixable(acc, _name, _params, nil), do: acc

  defp check_fixable(acc, name, params, body) do
    Enum.reduce(params, acc, fn param, a ->
      case param do
        {var_name, _, ctx} when is_atom(var_name) and (is_nil(ctx) or is_atom(ctx)) ->
          if uses_list_last?(body, var_name) and uses_append?(body, var_name) and
               uses_reverse?(body, var_name) do
            Map.put(a, {name, length(params)}, var_name)
          else
            a
          end

        _ ->
          a
      end
    end)
  end

  # --- Fix helpers: pass 2 — apply transforms ---

  defp apply_fix(
         {kind, meta, [{name, name_meta, params}, body_kw]} = node,
         fixable
       )
       when kind in [:def, :defp] and is_atom(name) and is_list(params) do
    case Map.get(fixable, {name, length(params)}) do
      nil ->
        node

      acc_var ->
        do_fix(node, kind, meta, name, name_meta, params, body_kw, acc_var)
    end
  end

  defp apply_fix(node, _fixable), do: node

  defp do_fix(node, kind, meta, name, name_meta, params, body_kw, acc_var) do
    body = extract_do_body(body_kw)

    case body do
      nil ->
        node

      body ->
        cond do
          # Recursive clause: has List.last(acc) — full rewrite
          uses_list_last?(body, acc_var) ->
            bound_var = find_list_last_bound_var(body, acc_var)
            new_params = rewrite_params(params, acc_var)
            head_var = {:head, [], nil}
            new_body = rewrite_body(body, acc_var, bound_var, head_var)
            new_body_kw = RuleHelpers.replace_do_body(body_kw, new_body)
            {kind, meta, [{name, name_meta, new_params}, new_body_kw]}

          # Base case / other clause: only has Enum.reverse(acc) — just remove it
          uses_reverse?(body, acc_var) ->
            new_body = remove_reverse(body, acc_var)
            new_body_kw = RuleHelpers.replace_do_body(body_kw, new_body)
            {kind, meta, [{name, name_meta, params}, new_body_kw]}

          # Neither pattern — leave unchanged
          true ->
            node
        end
    end
  end

  # Replace Enum.reverse(acc_var) with acc_var in the body
  defp remove_reverse(body, acc_var) do
    Macro.postwalk(body, fn
      {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, [{^acc_var, _, _}]} ->
        {acc_var, [], nil}

      node ->
        node
    end)
  end

  # Find the variable name assigned from `var_name = List.last(acc_var)`, or nil
  defp find_list_last_bound_var(body, acc_var) do
    {_ast, bound} =
      Macro.prewalk(body, nil, fn
        {:=, _,
         [
           {bound_name, _, bctx},
           {{:., _, [{:__aliases__, _, [:List]}, :last]}, _, [{^acc_var, _, _}]}
         ]} = node,
        _
        when is_atom(bound_name) and (is_nil(bctx) or is_atom(bctx)) ->
          {node, bound_name}

        node, acc ->
          {node, acc}
      end)

    bound
  end

  # Rewrite the body: remove assignment, replace vars, fix ++, remove Enum.reverse
  defp rewrite_body(body, acc_var, bound_var, head_var) do
    case body do
      {:__block__, meta, exprs} ->
        new_exprs =
          exprs
          |> Enum.reject(fn expr -> list_last_assignment?(expr, bound_var, acc_var) end)
          |> Enum.map(fn expr -> rewrite_expr(expr, acc_var, bound_var, head_var) end)

        {:__block__, meta, new_exprs}

      single ->
        if list_last_assignment?(single, bound_var, acc_var) do
          head_var
        else
          rewrite_expr(single, acc_var, bound_var, head_var)
        end
    end
  end

  # Check if an expression is `bound_var = List.last(acc_var)`
  defp list_last_assignment?(_expr, nil, _acc_var), do: false

  defp list_last_assignment?(
         {:=, _,
          [
            {bv, _, bctx},
            {{:., _, [{:__aliases__, _, [:List]}, :last]}, _, [{av, _, actx}]}
          ]},
         bound_var,
         acc_var
       )
       when is_atom(bv) and bv == bound_var and
              is_atom(av) and av == acc_var and
              (is_nil(bctx) or is_atom(bctx)) and
              (is_nil(actx) or is_atom(actx)),
       do: true

  defp list_last_assignment?(_, _, _), do: false

  # Apply replacements to a single expression
  defp rewrite_expr(expr, acc_var, bound_var, head_var) do
    Macro.postwalk(expr, fn
      # Replace bound_var → head
      {^bound_var, _, ctx} when is_atom(ctx) ->
        head_var

      # List.last(acc) → head (inline use without assignment)
      {{:., _, [{:__aliases__, _, [:List]}, :last]}, _, [{^acc_var, _, _}]} ->
        head_var

      # Enum.reverse(acc) → acc (remove reverse — prepend builds correct order)
      {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, [{^acc_var, _, _}]} ->
        {acc_var, [], nil}

      # acc ++ [expr] → [expr | acc]
      {:++, _, [{^acc_var, _, _}, {:__block__, _, [[e]]}]} ->
        {:__block__, [], [[{:|, [], [e, {acc_var, [], nil}]}]]}

      {:++, _, [{^acc_var, _, _}, [e]]} ->
        [{:|, [], [e, {acc_var, [], nil}]}]

      node ->
        node
    end)
  end

  # Rewrite the first bare acc var in params to [head | _] = acc
  defp rewrite_params(params, acc_var) do
    Enum.map(params, fn
      {^acc_var, pmeta, ctx} when is_atom(ctx) ->
        head = {:head, [], nil}
        underscore = {:_, [], nil}
        cons = {:__block__, [], [[{:|, [], [head, underscore]}]]}
        {:=, pmeta, [cons, {acc_var, pmeta, ctx}]}

      other ->
        other
    end)
  end

  defp extract_do_body(body_kw) when is_list(body_kw) do
    Enum.find_value(body_kw, fn
      {{:__block__, _, [:do]}, body} -> body
      _ -> nil
    end)
  end

  defp extract_do_body(_), do: nil

  defp build_issue(line) do
    %Issue{
      rule: :prefer_prepend_in_accumulator,
      message:
        "`List.last(acc)` combined with `acc ++ [expr]` is O(n²). " <>
          "Pattern-match the head with `[head | _] = acc` and use `[expr | acc]` instead.",
      meta: %{line: line}
    }
  end
end
