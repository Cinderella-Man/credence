defmodule Credence.Pattern.NoHdTlWhenConsBound do
  @moduledoc """
  Detects `hd(var)` / `tl(var)` calls in a function body where `var` is
  already bound to a non-empty list by an **anonymous** cons pattern
  (`var = [_ | _]` or `[_ | _] = var`) in the function clause head, and
  rewrites them to destructure `[head | tail]` in the head, using `head` /
  `tail` directly instead of `Kernel.hd/1` / `Kernel.tl/1`.

  Because the head pattern already guarantees `var` matched `[_ | _]` (a
  non-empty, possibly improper list), `hd(var)` is exactly the `head` and
  `tl(var)` is exactly the `tail` of a `[head | tail] = var` destructure —
  for every admitted value, including improper lists like `[1 | 2]`. The
  rewrite is therefore answer-preserving.

  ## Narrowing — the safe core

  The fix only fires when it is mechanically guaranteed safe:

  * **Anonymous cons only.** Only `[_ | _]` (both sides the bare `_`) is
    handled. A named cons (`[h | t]`, `[_head | _tail]`) already binds the
    parts and is left alone — promoting those would mean reusing or renaming
    existing (possibly underscore-suppressed) bindings.
  * **No rebinding in the body.** The body must contain no binding/scoping
    form (`=`, `fn`, `for`, `with`, `case`, `cond`, `receive`, `try`,
    `quote`). This rules out any inner scope that could shadow `var`, so a
    matched `hd(var)` / `tl(var)` unambiguously refers to the head binding.
  * **Keep the variable when it is still needed.** If `var` is referenced
    anywhere outside the rewritten `hd` / `tl` calls (a guard, another
    parameter, or elsewhere in the body), the `var = ...` binding is kept
    (`var = [head | tail]`); otherwise the whole binding collapses to the
    cons pattern (`[head | tail]`).

  ## Bad

      def first(list = [_ | _]), do: hd(list)
      def split(list = [_ | _]), do: {hd(list), tl(list)}

  ## Good

      def first([head | _]), do: head
      def split([head | tail]), do: {head, tail}
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  # Forms that introduce a binding or a new scope in the body. If any is
  # present we refuse to fix: an inner binding could shadow the cons-bound
  # variable, making a matched `hd(var)` ambiguous.
  @binding_forms [:=, :fn, :for, :with, :case, :cond, :receive, :try, :quote]

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case plan_clause(node) do
          {:plan, clause_issues, _new_def} -> {node, acc ++ clause_issues}
          :skip -> {node, acc}
        end
      end)

    issues
  end

  @impl true
  def fix_patches(ast, _opts) do
    transformed =
      Macro.prewalk(ast, fn node ->
        case plan_clause(node) do
          {:plan, _issues, new_def} -> new_def
          :skip -> node
        end
      end)

    RuleHelpers.patches_from_diff(ast, transformed)
  end

  # --- shared clause planner: drives both check and fix so they always agree ---

  # Returns `{:plan, issues, new_def_node}` when this `def`/`defp` clause has at
  # least one safely-fixable `hd(var)` / `tl(var)`, or `:skip` otherwise.
  defp plan_clause({kind, meta, [head, body_kw]})
       when kind in [:def, :defp] and is_list(body_kw) do
    with {:ok, call, guard} <- split_head(head),
         {fn_name, fn_meta, params} when is_list(params) <- call,
         {:ok, body} <- RuleHelpers.extract_do_body(body_kw),
         true <- scope_clean?(body) do
      taken0 = collect_var_names({kind, meta, [head, body_kw]})

      # Pass 1: pick fresh names and per-param replacement data.
      {plans, _taken} =
        Enum.map_reduce(params, taken0, fn param, taken ->
          plan_param(param, body, taken)
        end)

      flagged = for %{} = p <- plans, into: MapSet.new(), do: p.var

      if MapSet.size(flagged) == 0 do
        :skip
      else
        # Apply all body rewrites once, then decide keep-vs-drop per param.
        new_body =
          Enum.reduce(plans, body, fn
            %{} = p, b -> replace_uses(b, p.var, p.head_repl, p.tail_repl)
            _unchanged, b -> b
          end)

        new_params =
          plans
          |> Enum.with_index()
          |> Enum.map(fn
            {%{} = p, idx} -> finalize_param(p, new_body, guard, params, idx)
            {unchanged, _idx} -> unchanged
          end)

        new_call = {fn_name, fn_meta, new_params}
        new_head = rebuild_head(new_call, guard)
        new_def = {kind, meta, [new_head, RuleHelpers.replace_do_body(body_kw, new_body)]}

        {:plan, collect_issues(body, flagged), new_def}
      end
    else
      _ -> :skip
    end
  end

  defp plan_clause(_), do: :skip

  # Builds a replacement plan for one parameter, or returns the parameter
  # unchanged (passed through map_reduce's accumulator).
  defp plan_param(param, body, taken) do
    case cons_param(param) do
      {:ok, var, orient, var_node, eq_meta} ->
        needs_head = uses?(body, :hd, var)
        needs_tail = uses?(body, :tl, var)

        if needs_head or needs_tail do
          {head_name, taken} = maybe_name(:head, needs_head, taken)
          {tail_name, taken} = maybe_name(:tail, needs_tail, taken)

          plan = %{
            var: var,
            orient: orient,
            var_node: var_node,
            eq_meta: eq_meta,
            new_cons: [{:|, [], [pat(head_name), pat(tail_name)]}],
            head_repl: name_node(head_name),
            tail_repl: name_node(tail_name)
          }

          {plan, taken}
        else
          {param, taken}
        end

      :no ->
        {param, taken}
    end
  end

  defp maybe_name(_base, false, taken), do: {nil, taken}

  defp maybe_name(base, true, taken) do
    name = fresh_name(base, taken)
    {name, MapSet.put(taken, name)}
  end

  defp pat(nil), do: {:_, [], nil}
  defp pat(name), do: {name, [], nil}

  defp name_node(nil), do: nil
  defp name_node(name), do: {name, [], nil}

  # Keep `var = [head | tail]` when `var` is still used outside the rewritten
  # `hd`/`tl` calls; otherwise collapse to the bare cons pattern.
  defp finalize_param(plan, new_body, guard, params, idx) do
    others = List.delete_at(params, idx)

    used_elsewhere? =
      var_used?(new_body, plan.var) or
        guard_uses?(guard, plan.var) or
        Enum.any?(others, &var_used?(&1, plan.var))

    if used_elsewhere? do
      case plan.orient do
        :left -> {:=, plan.eq_meta, [plan.var_node, plan.new_cons]}
        :right -> {:=, plan.eq_meta, [plan.new_cons, plan.var_node]}
      end
    else
      plan.new_cons
    end
  end

  # --- head / guard plumbing ---

  defp split_head({:when, _wmeta, [call, guard]} = _head), do: {:ok, call, {:guard, guard}}
  defp split_head(call), do: {:ok, call, :no_guard}

  defp rebuild_head(new_call, :no_guard), do: new_call
  defp rebuild_head(new_call, {:guard, guard}), do: {:when, [], [new_call, guard]}

  defp guard_uses?(:no_guard, _var), do: false
  defp guard_uses?({:guard, guard}, var), do: var_used?(guard, var)

  # --- cons-bound parameter detection (anonymous `[_ | _]` only) ---

  defp cons_param({:=, eq_meta, [{name, _, ctx} = var_node, cons]})
       when is_atom(name) and is_atom(ctx) do
    if anon_cons?(cons), do: {:ok, name, :left, var_node, eq_meta}, else: :no
  end

  defp cons_param({:=, eq_meta, [cons, {name, _, ctx} = var_node]})
       when is_atom(name) and is_atom(ctx) do
    if anon_cons?(cons), do: {:ok, name, :right, var_node, eq_meta}, else: :no
  end

  defp cons_param(_), do: :no

  # `[_ | _]` with both sides the bare anonymous `_`. Sourceror wraps the
  # bracketed list in a `:__block__`; the raw `:|` form is matched too.
  defp anon_cons?({:__block__, _, [[{:|, _, [a, b]}]]}), do: underscore?(a) and underscore?(b)
  defp anon_cons?({:|, _, [a, b]}), do: underscore?(a) and underscore?(b)
  defp anon_cons?(_), do: false

  defp underscore?({:_, _, ctx}) when is_atom(ctx), do: true
  defp underscore?(_), do: false

  # --- body scanning ---

  defp scope_clean?(body) do
    {_ast, dirty?} =
      Macro.prewalk(body, false, fn
        {form, _, _} = node, _acc when form in @binding_forms -> {node, true}
        node, acc -> {node, acc}
      end)

    not dirty?
  end

  defp uses?(body, fn_name, var) do
    {_ast, found?} =
      Macro.prewalk(body, false, fn
        {^fn_name, _, [{^var, _, ctx}]} = node, _acc when is_atom(ctx) -> {node, true}
        node, acc -> {node, acc}
      end)

    found?
  end

  defp var_used?(ast, var) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {^var, _, ctx} = node, _acc when is_atom(ctx) -> {node, true}
        node, acc -> {node, acc}
      end)

    found?
  end

  defp collect_var_names(ast) do
    {_ast, names} =
      Macro.prewalk(ast, MapSet.new(), fn
        {name, _, ctx} = node, acc when is_atom(name) and is_atom(ctx) and name != :_ ->
          {node, MapSet.put(acc, name)}

        node, acc ->
          {node, acc}
      end)

    names
  end

  defp fresh_name(base, taken) do
    if MapSet.member?(taken, base) do
      Enum.find_value(1..1_000, fn i ->
        candidate = String.to_atom("#{base}#{i}")
        if MapSet.member?(taken, candidate), do: nil, else: candidate
      end)
    else
      base
    end
  end

  # Replace `hd(var)` -> head node and `tl(var)` -> tail node in the body.
  defp replace_uses(body, var, head_repl, tail_repl) do
    Macro.prewalk(body, fn
      {:hd, _, [{^var, _, ctx}]} when is_atom(ctx) and not is_nil(head_repl) -> head_repl
      {:tl, _, [{^var, _, ctx}]} when is_atom(ctx) and not is_nil(tail_repl) -> tail_repl
      node -> node
    end)
  end

  defp collect_issues(body, flagged) do
    {_ast, issues} =
      Macro.prewalk(body, [], fn
        {:hd, meta, [{var, _, ctx}]} = node, acc when is_atom(ctx) ->
          if MapSet.member?(flagged, var),
            do: {node, [build_issue(:hd, var, meta) | acc]},
            else: {node, acc}

        {:tl, meta, [{var, _, ctx}]} = node, acc when is_atom(ctx) ->
          if MapSet.member?(flagged, var),
            do: {node, [build_issue(:tl, var, meta) | acc]},
            else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  defp build_issue(:hd, var, meta) do
    %Issue{
      rule: :no_hd_tl_when_cons_bound,
      message:
        "`hd(#{var})` used on a variable already bound as `[_ | _]`. " <>
          "Prefer `[head | _]` destructuring in the function clause head.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp build_issue(:tl, var, meta) do
    %Issue{
      rule: :no_hd_tl_when_cons_bound,
      message:
        "`tl(#{var})` used on a variable already bound as `[_ | _]`. " <>
          "Prefer `[_ | tail]` destructuring in the function clause head.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
