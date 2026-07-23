defmodule Credence.Semantic.FixLocalFunctionInGuard do
  @moduledoc """
  Fixes the compile error caused by calling a local function inside a guard.

  LLMs sometimes define a helper like `defp is_range(x), do: is_map(x)` and
  then use it in a guard clause (`when is_range(x)`). The Elixir compiler
  rejects this because only macros (not local functions) can be invoked inside
  guards:

      "cannot find or invoke local is_range/1 inside a guard. Only macros can
       be invoked inside a guard and they must be defined before their
       invocation. Called as: is_range(length_range)"

  The fix inlines the helper into the guard — but only when the substitution
  is provably the same answer: the source must define exactly one `is_range/1`
  clause of the literal shape `def/defp is_range(param), do: is_map(param)`
  (no guard, no extra clauses). Then every guard call `is_range(arg)` is
  replaced with `is_map(arg)`, which is exact inlining of the helper's body.

  Anything else no-ops rather than risk a wrong edit (same policy as
  `FixHallucinatedEnumRange`): a helper defined some other way (e.g.
  `is_struct(x, Range)`, a `%Range{}` pattern match, multiple clauses), or no
  local `is_range/1` definition at all — in those cases the intended dispatch
  is unknowable from the source, so the diagnostic is left for a human.
  Only calls with exactly one argument inside guard position are rewritten;
  a plain variable named `is_range` and calls in function bodies are never
  touched.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "cannot find or invoke local is_range/1 inside a guard"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_local_function_in_guard,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         true <- is_map_alias_helper?(ast) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:when, when_meta, [fn_head, guard]}, acc ->
            {new_guard, guard_changed} = replace_local_fn_in_guard(guard)

            if guard_changed do
              {{:when, when_meta, [fn_head, new_guard]}, true}
            else
              {{:when, when_meta, [fn_head, guard]}, acc}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # The substitution is safe only when the helper is a pure alias for
  # `is_map/1`: exactly one `is_range/1` clause, unguarded, whose whole body is
  # `is_map` of the parameter. Then replacing the guard call inlines the body.
  defp is_map_alias_helper?(ast) do
    case local_is_range_defs(ast) do
      [{kind, _, [{:is_range, _, [{param, _, ctx}]}, body_kw]}]
      when kind in [:def, :defp] and is_atom(param) and is_atom(ctx) ->
        case body_of(body_kw) do
          {:ok, body} -> match?({:is_map, _, [{^param, _, _}]}, unwrap_block(body))
          :error -> false
        end

      _ ->
        false
    end
  end

  # Every def/defp clause for `is_range/1`, guarded heads included — more than
  # one clause (or a guarded one) fails the shape check above.
  defp local_is_range_defs(ast) do
    {_, defs} =
      Macro.prewalk(ast, [], fn
        {kind, _, [_ | _]} = node, acc when kind in [:def, :defp] ->
          if def_head(node) == {:is_range, 1}, do: {node, [node | acc]}, else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(defs)
  end

  defp def_head({_kind, _, [{:when, _, [call | _]} | _]}), do: call_name_arity(call)
  defp def_head({_kind, _, [call | _]}), do: call_name_arity(call)

  defp call_name_arity({name, _, args}) when is_atom(name) and is_list(args),
    do: {name, length(args)}

  defp call_name_arity(_), do: nil

  defp body_of([{{:__block__, _, [:do]}, body}]), do: {:ok, body}
  defp body_of([{:do, body}]), do: {:ok, body}
  defp body_of(_), do: :error

  defp unwrap_block({:__block__, _, [single]}), do: single
  defp unwrap_block(node), do: node

  # Replace `is_range(x)` with `is_map(x)` in a guard expression tree. Only
  # one-argument calls qualify — a bare variable named `is_range` has `nil`
  # args and must survive untouched.
  defp replace_local_fn_in_guard({:is_range, meta, [arg]}) do
    {new_arg, _} = replace_local_fn_in_guard(arg)
    {{:is_map, meta, [new_arg]}, true}
  end

  defp replace_local_fn_in_guard({op, meta, args}) when is_list(args) do
    {new_args, changed} =
      Enum.map_reduce(args, false, fn arg, acc ->
        {new_arg, arg_changed} = replace_local_fn_in_guard(arg)
        {new_arg, acc || arg_changed}
      end)

    {{op, meta, new_args}, changed}
  end

  defp replace_local_fn_in_guard(node), do: {node, false}

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
