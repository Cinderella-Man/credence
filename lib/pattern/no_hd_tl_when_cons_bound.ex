defmodule Credence.Pattern.NoHdTlWhenConsBound do
  @moduledoc """
  Check-only rule: detects `hd(var)` / `tl(var)` calls in function bodies
  where `var` is already bound as a non-empty list in the function clause head
  (e.g., `var = [_ | _]` or `[_ | _] = var`).

  When a parameter is known to be a cons cell via a pattern that binds the
  whole list, prefer destructuring `[head | tail]` in the function clause
  head and using `head` / `tail` directly instead of calling `Kernel.hd/1`
  or `Kernel.tl/1` in the body.

  ## Bad

      def first(list = [_ | _]), do: hd(list)
      def split(list = [_ | _]), do: {hd(list), tl(list)}
      def merge(list1 = [_ | _], list2 = [_ | _]) when list1 >= list2,
        do: [hd(list1) | merge(tl(list1), list2)]

  ## Good

      def first([head | _tail]), do: head
      def split([head | tail]), do: {head, tail}
      def merge([h1 | t1] = list1, [_ | _] = list2) when list1 >= list2,
        do: [h1 | merge(t1, list2)]
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {def_type, _meta, [head, body_kw]} = node, issues
        when def_type in [:def, :defp] and is_list(body_kw) ->
          params = extract_params_from_head(head)
          cons_bound = collect_cons_bound_vars(params)

          if cons_bound == [] do
            {node, issues}
          else
            case RuleHelpers.extract_do_body(body_kw) do
              {:ok, body} ->
                body_issues = find_hd_tl(body, cons_bound)
                {node, Enum.reverse(body_issues) ++ issues}

              :error ->
                {node, issues}
            end
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # --- helpers ---

  # Extract the parameter list from a function head, handling `when` guards.
  defp extract_params_from_head({:when, _, [{_fn, _, params}, _guard]})
       when is_list(params),
       do: params

  defp extract_params_from_head({:when, _, [{_fn, _, _}, _guard]}), do: []
  defp extract_params_from_head({_fn, _, params}) when is_list(params), do: params
  defp extract_params_from_head({_fn, _, _}), do: []
  defp extract_params_from_head(_), do: []

  # Collect variable names from params that are bound to a cons cell pattern.
  # Matches `var = [_ | _]` and `[_ | _] = var`.
  defp collect_cons_bound_vars(params) do
    Enum.flat_map(params, fn
      {:=, _, [{name, _, ctx}, cons]} when is_atom(name) and is_atom(ctx) ->
        if cons_pattern?(cons), do: [name], else: []

      {:=, _, [cons, {name, _, ctx}]} when is_atom(name) and is_atom(ctx) ->
        if cons_pattern?(cons), do: [name], else: []

      _ ->
        []
    end)
  end

  # Any cons-cell pattern: [_ | _], [h | t], [_ | rest], etc.
  # Sourceror wraps bracket-delimited expressions in {:__block__, meta, [[...]]}.
  defp cons_pattern?({:__block__, _, [[{:|, _, [_, _]}]]}), do: true
  defp cons_pattern?({:|, _, [_, _]}), do: true
  defp cons_pattern?(_), do: false

  # Walk the body AST and find `hd(var)` / `tl(var)` calls where `var`
  # is one of the cons-bound variables.
  defp find_hd_tl(body, cons_bound) do
    var_set = MapSet.new(cons_bound)

    {_ast, issues} =
      Macro.prewalk(body, [], fn
        {fn_name, meta, [{var_name, _, ctx}]} = node, issues
        when is_atom(fn_name) and fn_name in [:hd, :tl] and
               is_atom(var_name) and is_atom(ctx) ->
          if MapSet.member?(var_set, var_name) do
            {node, [build_issue(fn_name, var_name, meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    issues
  end

  defp build_issue(:hd, var, meta) do
    %Issue{
      rule: :no_hd_tl_when_cons_bound,
      message:
        "`hd(#{var})` used on a variable already bound as `[_ | _]`. " <>
          "Prefer `[head | _tail]` destructuring in the function clause head.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp build_issue(:tl, var, meta) do
    %Issue{
      rule: :no_hd_tl_when_cons_bound,
      message:
        "`tl(#{var})` used on a variable already bound as `[_ | _]`. " <>
          "Prefer `[_head | tail]` destructuring in the function clause head.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
