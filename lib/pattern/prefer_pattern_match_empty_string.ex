defmodule Credence.Pattern.PreferPatternMatchEmptyString do
  @moduledoc """
  Detects `byte_size(var) == 0` in function guards that can be replaced with
  pattern matching `""` directly in the function head.

  LLMs reach for `byte_size/1` guards to check for empty strings because
  many languages check `.length == 0` or `.size() == 0`. In Elixir, pattern
  matching `""` in the function head is shorter, clearer, and more idiomatic.

  ## Bad

      def reverse_left_words(str, _count) when byte_size(str) == 0, do: str
      def process(str) when byte_size(str) == 0, do: :empty

  ## Good

      def reverse_left_words("" = str, _count), do: str
      def process(""), do: :empty

  ## What is flagged

  Any `def`/`defp` clause whose guard contains `byte_size(param) == 0` where
  `param` is a top-level simple parameter. The `byte_size` check may be the
  sole guard or a direct conjunct in an `and` chain.

  Not flagged:
  - `byte_size(var) == 0` inside `or`
  - `byte_size(var) != 0` (negated check)
  - `byte_size(expr) == 0` where expr is not a simple variable
  - `byte_size(var) == N` where N != 0

  ## Auto-fix

  Replaces the parameter with `""` in the function head and removes
  `byte_size(param) == 0` from the guard (or drops the guard entirely if it
  was the only condition). When the parameter is used in the function
  body, the fix uses `"" = param` to preserve the binding.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

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

    if params != [] and has_fixable_byte_size_zero?(guard, params) do
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

  # Walk the guard looking for byte_size(param) == 0 — only recurse
  # into `and` nodes, stop at `or` / `not` / `!`
  defp has_fixable_byte_size_zero?({:==, _, [{:byte_size, _, [{name, _, ctx}]}, zero]}, params)
       when is_atom(name) and is_atom(ctx) do
    case unwrap_int(zero) do
      0 -> name in params
      _ -> false
    end
  end

  defp has_fixable_byte_size_zero?({:==, _, [zero, {:byte_size, _, [{name, _, ctx}]}]}, params)
       when is_atom(name) and is_atom(ctx) do
    case unwrap_int(zero) do
      0 -> name in params
      _ -> false
    end
  end

  defp has_fixable_byte_size_zero?({:and, _, [left, right]}, params),
    do: has_fixable_byte_size_zero?(left, params) or has_fixable_byte_size_zero?(right, params)

  defp has_fixable_byte_size_zero?({:or, _, _}, _params), do: false
  defp has_fixable_byte_size_zero?({:not, _, _}, _params), do: false
  defp has_fixable_byte_size_zero?({:!, _, _}, _params), do: false
  defp has_fixable_byte_size_zero?(_, _params), do: false

  defp unwrap_int({:__block__, _, [n]}) when is_integer(n), do: n
  defp unwrap_int(n) when is_integer(n), do: n
  defp unwrap_int(_), do: nil

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

  defp build_when_patch(when_node, fn_head, guard, body_rest) do
    params = top_level_param_names(fn_head)

    if params != [] and has_fixable_byte_size_zero?(guard, params) and
         not guard_has_disallowed?(guard) do
      bs_params = collect_bs_params(guard, params)

      if bs_params == [] do
        nil
      else
        {_fn_name, _fm, fn_args} = fn_head
        body_used = used_in_body?(bs_params, body_rest)
        new_fn_args = Enum.map(fn_args, &maybe_replace_param(&1, bs_params, body_used))
        new_fn_head = put_elem(fn_head, 2, new_fn_args)

        remaining_guard = remove_byte_size_zero_from_guard(guard, bs_params)

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

  defp collect_bs_params({:==, _, [{:byte_size, _, [{name, _, ctx}]}, zero]}, params)
       when is_atom(name) and is_atom(ctx) do
    if name in params and unwrap_int(zero) == 0, do: [name], else: []
  end

  defp collect_bs_params({:==, _, [zero, {:byte_size, _, [{name, _, ctx}]}]}, params)
       when is_atom(name) and is_atom(ctx) do
    if name in params and unwrap_int(zero) == 0, do: [name], else: []
  end

  defp collect_bs_params({:and, _, [l, r]}, params),
    do: Enum.uniq(collect_bs_params(l, params) ++ collect_bs_params(r, params))

  defp collect_bs_params(_, _params), do: []

  defp maybe_replace_param({name, _meta, ctx} = node, bs_params, body_used)
       when is_atom(name) and is_atom(ctx) do
    if name in bs_params do
      if MapSet.member?(body_used, name) do
        # Keep binding: "" = var
        {:=, [], [{:__block__, [delimiter: "\""], [""]}, {name, [line: 0, column: 0], nil}]}
      else
        # Drop binding: just ""
        {:__block__, [delimiter: "\""], [""]}
      end
    else
      node
    end
  end

  defp maybe_replace_param(other, _bs_params, _body_used), do: other

  defp used_in_body?(bs_params, body_rest) do
    bs_params
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

  defp remove_byte_size_zero_from_guard(
         {:==, _, [{:byte_size, _, [{name, _, ctx}]}, zero]} = node,
         bs_params
       )
       when is_atom(name) and is_atom(ctx) do
    if name in bs_params and unwrap_int(zero) == 0, do: nil, else: node
  end

  defp remove_byte_size_zero_from_guard(
         {:==, _, [zero, {:byte_size, _, [{name, _, ctx}]}]} = node,
         bs_params
       )
       when is_atom(name) and is_atom(ctx) do
    if name in bs_params and unwrap_int(zero) == 0, do: nil, else: node
  end

  defp remove_byte_size_zero_from_guard({:and, meta, [l, r]}, bs_params) do
    case {remove_byte_size_zero_from_guard(l, bs_params),
          remove_byte_size_zero_from_guard(r, bs_params)} do
      {nil, nil} -> nil
      {nil, remaining} -> remaining
      {remaining, nil} -> remaining
      {l2, r2} -> {:and, meta, [l2, r2]}
    end
  end

  defp remove_byte_size_zero_from_guard(other, _bs_params), do: other

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_pattern_match_empty_string,
      message: """
      `byte_size(var) == 0` in a guard can be replaced with pattern \
      matching `""` directly in the function head.

          def f(str) when byte_size(str) == 0    →    def f("")
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
