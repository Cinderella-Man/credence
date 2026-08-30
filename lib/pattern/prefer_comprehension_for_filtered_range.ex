defmodule Credence.Pattern.PreferComprehensionForFilteredRange do
  @moduledoc """
  Detects `Enum.reduce/3` over a range that filters elements into an
  accumulator list followed by `Enum.reverse/1`, and rewrites it as a
  `for` comprehension with a guard.

  This pattern is idiomatic Elixir — a `for` comprehension with a filter
  expresses the same intent more clearly and avoids building + reversing
  an intermediate list.

  ## Bad

      Enum.reduce(1..n, [], fn num, missing ->
        if MapSet.member?(present, num), do: missing, else: [num | missing]
      end)
      |> Enum.reverse()

  ## Good

      for num <- 1..n, !MapSet.member?(present, num), do: num
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    ast
    |> eligible_nodes()
    |> Enum.map(fn node ->
      {:ok, meta} = detect_pattern(node)
      build_issue(meta)
    end)
  end

  @impl true
  def fix_patches(ast, _opts) do
    eligible = ast |> eligible_nodes() |> MapSet.new()

    RuleHelpers.patches_from_postwalk(ast, fn node ->
      if MapSet.member?(eligible, node), do: rewrite(node), else: node
    end)
  end

  # A bare `Enum` is resolved lexically. Track aliases in source order so check
  # and fix share one admission decision, and never rewrite a call that actually
  # targets a user module imported as `Enum`.
  defp eligible_nodes(ast) do
    {nodes, _enum_shadowed?} = collect_eligible(ast, [], false)
    Enum.reverse(nodes)
  end

  defp collect_eligible({:quote, _, _args}, nodes, shadowed?), do: {nodes, shadowed?}

  defp collect_eligible({:__block__, _, expressions}, nodes, shadowed?) do
    Enum.reduce(expressions, {nodes, shadowed?}, fn expression, {acc, current_shadowed?} ->
      collect_eligible(expression, acc, current_shadowed?)
    end)
  end

  defp collect_eligible({:alias, _, args}, nodes, shadowed?) do
    {nodes, shadowed? or alias_shadows_enum?(args)}
  end

  defp collect_eligible(node, nodes, shadowed?)
       when is_tuple(node) and tuple_size(node) == 3 do
    {_form, _meta, args} = node

    nodes =
      if not shadowed? and match?({:ok, _}, detect_pattern(node)),
        do: [node | nodes],
        else: nodes

    if is_list(args) do
      nodes =
        Enum.reduce(args, nodes, fn arg, acc ->
          {acc, _nested_shadowed?} = collect_eligible(arg, acc, shadowed?)
          acc
        end)

      {nodes, shadowed?}
    else
      {nodes, shadowed?}
    end
  end

  defp collect_eligible({left, right}, nodes, shadowed?) do
    {nodes, _} = collect_eligible(left, nodes, shadowed?)
    {nodes, shadowed?} = collect_eligible(right, nodes, shadowed?)
    {nodes, shadowed?}
  end

  defp collect_eligible(nodes, acc, shadowed?) when is_list(nodes) do
    collected =
      Enum.reduce(nodes, acc, fn node, inner_acc ->
        {inner_acc, _} = collect_eligible(node, inner_acc, shadowed?)
        inner_acc
      end)

    {collected, shadowed?}
  end

  defp collect_eligible(_node, nodes, shadowed?), do: {nodes, shadowed?}

  defp alias_shadows_enum?([
         {:__aliases__, _, target},
         [{{:__block__, _, [:as]}, {:__aliases__, _, [:Enum]}}]
       ]),
       do: target not in [[:Enum], [:"Elixir", :Enum]]

  defp alias_shadows_enum?([{:__aliases__, _, target}]) do
    List.last(target) == :Enum and target not in [[:Enum], [:"Elixir", :Enum]]
  end

  defp alias_shadows_enum?(_args), do: false

  # ── Detection ──────────────────────────────────────────────────────────

  # Piped: Enum.reduce(range, [], fn ...) |> Enum.reverse()
  defp detect_pattern(
         {:|>, meta,
          [
            {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, reduce_args},
            {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, []}
          ]}
       ) do
    detect_reduce_pattern(reduce_args, meta)
  end

  # Direct: Enum.reverse(Enum.reduce(range, [], fn ...))
  defp detect_pattern(
         {{:., meta, [{:__aliases__, _, [:Enum]}, :reverse]}, _,
          [
            {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, reduce_args}
          ]}
       ) do
    detect_reduce_pattern(reduce_args, meta)
  end

  defp detect_pattern(_), do: :error

  # Validates the reduce arguments:
  #   - First arg is a range (`first..last` or the explicit-step `first..last//step`)
  #   - Second arg is an empty list accumulator
  #   - Third arg is an fn with the if-prepend-in-else body
  defp detect_reduce_args([
         range,
         {:__block__, _, [[]]},
         {:fn, _, [{:->, _, [params, body]}]}
       ]) do
    range?(range) and filter_body?(params, body)
  end

  defp detect_reduce_args(_), do: false

  # A range literal — `first..last` or the explicit-step `first..last//step`. The
  # rewrite embeds the range AST verbatim, so a stepped range carries through
  # unchanged (and `1..n//1` is the warning-free form when `last` may be `< first`).
  defp range?({:.., _, [_, _]}), do: true
  defp range?({:..//, _, [_, _, _]}), do: true
  defp range?(_), do: false

  defp detect_reduce_pattern(reduce_args, meta) do
    if detect_reduce_args(reduce_args) do
      {:ok, meta}
    else
      :error
    end
  end

  # The fn body must be EXACTLY:
  #   if CONDITION, do: <acc>, else: [<elem> | <acc>]
  # where `<elem>` is the fn's first parameter and `<acc>` is the second, the
  # do-branch returns the accumulator unchanged, and the else-branch prepends
  # the element to it. We tie the cons-cell names to the actual parameters:
  # the rewrite always yields the first parameter (`for elem <- range, ...`),
  # so a body that prepends some *other* variable (`[other | acc]`) would
  # silently change the result and must NOT be flagged.
  #
  # CONDITION must not reference the accumulator: the comprehension has no
  # accumulator binding, so `if length(acc) > k, ...` cannot carry through.
  defp filter_body?(
         [{p1, _, nil}, {p2, _, nil}],
         {:if, _,
          [
            condition,
            [
              {{:__block__, _, [:do]}, {do_name, _, nil}},
              {{:__block__, _, [:else]},
               {:__block__, _, [[{:|, _, [{elem_name, _, nil}, {acc_name, _, nil}]}]]}}
            ]
          ]}
       )
       when is_atom(p1) and is_atom(p2) and p1 != p2 and
              do_name == p2 and elem_name == p1 and acc_name == p2 do
    not references_var?(condition, p2)
  end

  defp filter_body?(_, _), do: false

  # True if `name` appears as a bare variable reference anywhere in `ast`
  # (a node `{name, _, context}` whose context is an atom/nil, i.e. not a
  # call where the third element is an argument list).
  defp references_var?(ast, name) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {^name, _, context} = node, _acc when is_atom(context) -> {node, true}
        node, acc -> {node, acc}
      end)

    found?
  end

  # ── Rewrite ────────────────────────────────────────────────────────────

  # Piped form
  defp rewrite(
         {:|>, _,
          [
            {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _,
             [range, {:__block__, _, [[]]}, fn_ast]},
            {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, []}
          ]} = node
       ) do
    carry_discarded_comments(build_comprehension(range, fn_ast), node)
  end

  # Direct form
  defp rewrite(
         {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _,
          [
            {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _,
             [range, {:__block__, _, [[]]}, fn_ast]}
          ]} = node
       ) do
    carry_discarded_comments(build_comprehension(range, fn_ast), node)
  end

  defp carry_discarded_comments(replacement, original) do
    discarded =
      RuleHelpers.collect_comments(original) -- RuleHelpers.collect_comments(replacement)

    replacement
    |> inherit_position(original)
    |> RuleHelpers.carry_comments(discarded, [])
  end

  defp inherit_position({form, meta, args}, {_original_form, original_meta, _original_args}) do
    position = Keyword.take(original_meta, [:line, :column])
    {form, Keyword.merge(meta, position), args}
  end

  # ── Comprehension builder ──────────────────────────────────────────────

  defp build_comprehension(range, {:fn, _, [{:->, _, [params, body]}]}) do
    [num_pat, _acc_pat] = params
    {num_name, _, _} = num_pat

    condition = extract_negated_condition(body)

    {:for, [],
     [
       {:<-, [], [num_pat, range]},
       condition,
       [{{:__block__, [format: :keyword], [:do]}, {num_name, [], nil}}]
     ]}
  end

  # Extract the negated condition from the if-expression body.
  # The body is: if MapSet.member?(present, num), do: acc, else: [num | acc]
  # We want: !MapSet.member?(present, num)
  defp extract_negated_condition(
         {:if, _,
          [
            condition,
            [
              {{:__block__, _, [:do]}, _acc},
              {{:__block__, _, [:else]}, _cons_list}
            ]
          ]}
       ) do
    {:!, [line: nil], [condition]}
  end

  # ── Issue builder ──────────────────────────────────────────────────────

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_comprehension_for_filtered_range,
      message:
        "`Enum.reduce/3` with accumulator prepend and `Enum.reverse/1` over a range " <>
          "can be replaced with a `for` comprehension with a guard filter.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
