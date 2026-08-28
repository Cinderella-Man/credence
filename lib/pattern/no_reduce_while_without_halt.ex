defmodule Credence.Pattern.NoReduceWhileWithoutHalt do
  @moduledoc """
  Detects `Enum.reduce_while/3` where every callback clause returns only
  `{:cont, value}` — never `:halt` or `{:halt, value}`. This is equivalent
  to plain `Enum.reduce/3` and the `reduce_while` adds unnecessary ceremony.

  ## Bad

      Enum.reduce_while(list, 0, fn x, acc ->
        {:cont, acc + x}
      end)

      list
      |> Enum.reduce_while({0, []}, fn h, {max, acc} ->
        new_max = max(h, max)
        {:cont, {new_max, [new_max | acc]}}
      end)

  ## Good

      Enum.reduce(list, 0, fn x, acc ->
        acc + x
      end)

      list
      |> Enum.reduce({0, []}, fn h, {max, acc} ->
        new_max = max(h, max)
        {new_max, [new_max | acc]}
      end)

  ## Auto-fix

  Replaces `reduce_while` with `reduce` and unwraps each `{:cont, value}`
  return to just `value`.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    enum_shadowed? = enum_alias_shadowed?(ast)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., _, _} = dot, meta, args} = node, issues when is_list(args) ->
          if not enum_shadowed? and reduce_while_call?(dot) and length(args) >= 2 do
            fn_node = List.last(args)

            if all_cont?(fn_node) do
              {node, [build_issue(meta) | issues]}
            else
              {node, issues}
            end
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.get(opts, :source, "")
    enum_shadowed? = enum_alias_shadowed?(ast)
    RuleHelpers.patches_from_postwalk(ast, &maybe_rewrite(&1, source, enum_shadowed?))
  end

  defp reduce_while_call?({:., _, [{:__aliases__, _, [:Enum]}, :reduce_while]}), do: true
  defp reduce_while_call?({:., _, [:Enum, :reduce_while]}), do: true
  defp reduce_while_call?(_), do: false

  defp reduce_call(
         {:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, :reduce_while]},
         call_meta
       ) do
    {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, :reduce]}, call_meta}
  end

  defp reduce_call({:., dot_meta, [:Enum, :reduce_while]}, call_meta) do
    {{:., dot_meta, [:Enum, :reduce]}, call_meta}
  end

  # Returns true if every clause of the anonymous function returns only
  # {:cont, _} and never :halt or {:halt, _}.
  defp all_cont?({:fn, _, clauses}) when is_list(clauses) do
    Enum.all?(clauses, &clause_all_cont?/1)
  end

  defp all_cont?(_), do: false

  defp clause_all_cont?({:->, _, [_args, body]}) do
    not halts?(body) and returns_cont?(body)
  end

  defp clause_all_cont?(_), do: false

  # Check if the body contains any :halt or {:halt, _} return.
  defp halts?(body) do
    {_, found} =
      Macro.prewalk(body, false, fn
        node, true ->
          {node, true}

        node, false ->
          if halt_value?(node) do
            {node, true}
          else
            {node, false}
          end
      end)

    found
  end

  defp halt_value?(:halt), do: true
  defp halt_value?({:__block__, _, [:halt]}), do: true
  defp halt_value?({:halt, _}), do: true
  # Sourceror wraps 2-tuples: {a, b} → {{:__block__, _, [a]}, b}
  defp halt_value?({{:__block__, _, [:halt]}, _}), do: true
  defp halt_value?({:__block__, _, [{:halt, _}]}), do: true
  defp halt_value?(_), do: false

  # Check that the body returns {:cont, _} as its last expression.
  defp returns_cont?({:__block__, _meta, stmts}) when is_list(stmts) do
    case List.last(stmts) do
      nil -> false
      last -> cont_value?(last)
    end
  end

  defp returns_cont?(single), do: cont_value?(single)

  defp cont_value?({:cont, _}), do: true
  # Sourceror wraps 2-tuples: {:cont, v} → {{:__block__, _, [:cont]}, v}
  defp cont_value?({{:__block__, _, [:cont]}, _}), do: true
  defp cont_value?({:__block__, _, [{:cont, _}]}), do: true
  defp cont_value?({:__block__, _, [{{:__block__, _, [:cont]}, _}]}), do: true
  defp cont_value?(_), do: false

  # Rewrite: replace reduce_while → reduce, unwrap {:cont, value} → value
  defp maybe_rewrite(
         {{:., _, _} = dot, call_meta, args} = node,
         _source,
         enum_shadowed?
       ) do
    if not enum_shadowed? and reduce_while_call?(dot) and length(args) >= 2 do
      fn_node = List.last(args)

      if all_cont?(fn_node) do
        {new_dot, _} = reduce_call(dot, call_meta)
        new_args = List.update_at(args, -1, &unwrap_cont_fn/1)
        {new_dot, call_meta, new_args}
      else
        node
      end
    else
      node
    end
  end

  defp maybe_rewrite(node, _source, _enum_shadowed?), do: node

  defp enum_alias_shadowed?(ast) do
    {_ast, shadowed?} =
      Macro.prewalk(ast, false, fn
        {:alias, _, [{:__aliases__, _, target}, opts]} = node, shadowed?
        when is_list(target) and is_list(opts) ->
          {node, shadowed? or shadows_enum?(target, alias_as(opts))}

        {:alias, _, [{:__aliases__, _, target}]} = node, shadowed? when is_list(target) ->
          {node, shadowed? or shadows_enum?(target, nil)}

        node, shadowed? ->
          {node, shadowed?}
      end)

    shadowed?
  end

  defp alias_as(opts) do
    Enum.find_value(opts, fn
      {:as, value} -> value
      {{:__block__, _, [:as]}, value} -> value
      _other -> nil
    end)
  end

  defp shadows_enum?(target, {:__aliases__, _, [:Enum]}), do: target != [:Enum]
  defp shadows_enum?(target, nil), do: List.last(target) == :Enum and target != [:Enum]
  defp shadows_enum?(_target, _as), do: false

  defp unwrap_cont_fn({:fn, fn_meta, clauses}) do
    new_clauses = Enum.map(clauses, &unwrap_cont_clause/1)
    {:fn, fn_meta, new_clauses}
  end

  defp unwrap_cont_clause({:->, arrow_meta, [args, body]}) do
    {:->, arrow_meta, [args, unwrap_cont_body(body)]}
  end

  defp unwrap_cont_body({:cont, value}), do: value
  # Sourceror wraps 2-tuples: {:cont, v} → {{:__block__, _, [:cont]}, v}
  defp unwrap_cont_body({{:__block__, _, [:cont]}, value}), do: value
  defp unwrap_cont_body({:__block__, meta, [{:cont, value}]}), do: {:__block__, meta, [value]}

  defp unwrap_cont_body({:__block__, meta, [{{:__block__, _, [:cont]}, value}]}),
    do: {:__block__, meta, [value]}

  defp unwrap_cont_body({:__block__, meta, stmts}) when is_list(stmts) do
    {init, [last]} = Enum.split(stmts, -1)
    {:__block__, meta, init ++ [unwrap_cont_body(last)]}
  end

  defp unwrap_cont_body(other), do: other

  defp build_issue(meta) do
    %Issue{
      rule: :no_reduce_while_without_halt,
      message:
        "`Enum.reduce_while/3` used where every clause returns `{:cont, ...}` " <>
          "and none returns `:halt`. Use `Enum.reduce/3` instead — it is " <>
          "equivalent and avoids unnecessary `{:cont, ...}` wrapping.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
