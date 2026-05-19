defmodule Credence.Pattern.NoIsNilGuard do
  @moduledoc """
  Detects `is_nil(param)` in function guards that can be replaced with
  pattern matching `nil` directly in the function head.

  LLMs reach for `is_nil/1` in guards because Python uses
  `if x is None:` — the explicit nil/null check is the only option.
  In Elixir, pattern matching `nil` in the function head is shorter,
  clearer, and more idiomatic.

  ## Bad

      def foo(x) when is_nil(x), do: :default
      def bar(x, y) when is_nil(x) and is_binary(y), do: y

  ## Good

      def foo(nil), do: :default
      def bar(nil, y) when is_binary(y), do: y

  ## What is flagged

  Any `def`/`defp` clause whose guard contains `is_nil(param)` where
  `param` is a top-level simple parameter. The `is_nil` may be the sole
  guard or a direct conjunct in an `and` chain.

  Not flagged:
  - `is_nil` inside `or` (`when is_nil(x) or is_atom(x)`)
  - negated `is_nil` (`when not is_nil(x)`)
  - `is_nil` on non-variable expressions (`when is_nil(hd(x))`)
  - `is_nil` on destructured bindings (`def foo(%{k: v}) when is_nil(v)`)
  - `is_nil` outside of function guards (e.g. inside `if`)

  ## Auto-fix

  Replaces the parameter with `nil` in the function head and removes
  `is_nil(param)` from the guard (or drops the guard entirely if it
  was the only condition). When the parameter is used in the function
  body, the fix uses `nil = param` to preserve the binding.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  # ── Check ──────────────────────────────────────────────────────

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case detect(node) do
          {:ok, meta} -> {node, [build_issue(meta) | acc]}
          :skip -> {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  # def/defp with a when clause
  defp detect({def_kind, meta, [{:when, _wm, [fn_head, guard]} | _]})
       when def_kind in [:def, :defp] do
    params = top_level_param_names(fn_head)

    if params != [] and has_fixable_is_nil?(guard, params) do
      {:ok, meta}
    else
      :skip
    end
  end

  defp detect(_), do: :skip

  # Extract simple top-level param names: {name, _, ctx} where both atoms
  defp top_level_param_names({_name, _meta, params}) when is_list(params) do
    for {n, _, ctx} <- params, is_atom(n), is_atom(ctx), do: n
  end

  defp top_level_param_names(_), do: []

  # Walk the guard looking for bare is_nil(param) — only recurse
  # into `and` nodes, stop at `or` / `not` / `!`
  defp has_fixable_is_nil?({:is_nil, _, [{name, _, ctx}]}, params)
       when is_atom(name) and is_atom(ctx),
       do: name in params

  defp has_fixable_is_nil?({:and, _, [left, right]}, params),
    do: has_fixable_is_nil?(left, params) or has_fixable_is_nil?(right, params)

  defp has_fixable_is_nil?({:or, _, _}, _), do: false
  defp has_fixable_is_nil?({:not, _, _}, _), do: false
  defp has_fixable_is_nil?({:!, _, _}, _), do: false
  defp has_fixable_is_nil?(_, _), do: false

  # ── Fix ────────────────────────────────────────────────────────

  @impl true
  def fix_patches(ast, _opts) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn
        {def_kind, _meta, [{:when, _wm, [fn_head, guard]} = when_node | rest]} = node, acc
        when def_kind in [:def, :defp] ->
          case build_when_patch(when_node, fn_head, guard, rest) do
            nil -> {node, acc}
            patch -> {node, [patch | acc]}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(patches)
  end

  # Builds a patch replacing the `when` node's source range with the
  # rewritten function head: params with `nil`/`nil = param`, plus the
  # (possibly empty) remaining guard.
  defp build_when_patch(when_node, fn_head, guard, body_rest) do
    params = top_level_param_names(fn_head)

    if params != [] and has_fixable_is_nil?(guard, params) and not guard_has_disallowed?(guard) do
      nil_params = collect_nil_params(guard, params)

      if nil_params == [] do
        nil
      else
        {_fn_name, _fm, fn_args} = fn_head
        body_used = used_in_body?(nil_params, body_rest)
        new_fn_args = Enum.map(fn_args, &maybe_replace_param(&1, nil_params, body_used))
        new_fn_head = put_elem(fn_head, 2, new_fn_args)

        remaining_guard = remove_is_nil_from_guard(guard, nil_params)

        head_source =
          case remaining_guard do
            nil -> Macro.to_string(new_fn_head)
            g -> "#{Macro.to_string(new_fn_head)} when #{Macro.to_string(g)}"
          end

        %{range: Sourceror.get_range(when_node), change: head_source}
      end
    end
  end

  defp guard_has_disallowed?({:or, _, _}), do: true
  defp guard_has_disallowed?({:not, _, _}), do: true
  defp guard_has_disallowed?({:!, _, _}), do: true

  defp guard_has_disallowed?({:and, _, [l, r]}),
    do: guard_has_disallowed?(l) or guard_has_disallowed?(r)

  defp guard_has_disallowed?(_), do: false

  defp collect_nil_params({:is_nil, _, [{name, _, ctx}]}, params)
       when is_atom(name) and is_atom(ctx) do
    if name in params, do: [name], else: []
  end

  defp collect_nil_params({:and, _, [l, r]}, params),
    do: Enum.uniq(collect_nil_params(l, params) ++ collect_nil_params(r, params))

  defp collect_nil_params(_, _), do: []

  defp maybe_replace_param({name, _meta, ctx} = node, nil_params, body_used)
       when is_atom(name) and is_atom(ctx) do
    if name in nil_params do
      if MapSet.member?(body_used, name) do
        {:=, [], [nil, node]}
      else
        nil
      end
    else
      node
    end
  end

  defp maybe_replace_param(other, _nil_params, _body_used), do: other

  defp used_in_body?(nil_params, body_rest) do
    nil_params
    |> Enum.filter(fn name ->
      {_, found} =
        Macro.prewalk(body_rest, false, fn
          {^name, _, ctx} = n, _acc when is_atom(ctx) -> {n, true}
          n, acc -> {n, acc}
        end)

      found
    end)
    |> MapSet.new()
  end

  defp remove_is_nil_from_guard({:is_nil, _, [{name, _, ctx}]} = node, nil_params)
       when is_atom(name) and is_atom(ctx) do
    if name in nil_params, do: nil, else: node
  end

  defp remove_is_nil_from_guard({:and, meta, [l, r]}, nil_params) do
    case {remove_is_nil_from_guard(l, nil_params), remove_is_nil_from_guard(r, nil_params)} do
      {nil, nil} -> nil
      {nil, remaining} -> remaining
      {remaining, nil} -> remaining
      {l2, r2} -> {:and, meta, [l2, r2]}
    end
  end

  defp remove_is_nil_from_guard(other, _), do: other

  # ── Issue ──────────────────────────────────────────────────────

  defp build_issue(meta) do
    %Issue{
      rule: :no_is_nil_guard,
      message: """
      `is_nil(param)` in a guard can be replaced with pattern \
      matching `nil` directly in the function head.

          def foo(x) when is_nil(x)    →    def foo(nil)
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
