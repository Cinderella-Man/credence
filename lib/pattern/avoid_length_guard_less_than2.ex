defmodule Credence.Pattern.AvoidLengthGuardLessThan2 do
  @moduledoc """
  Performance rule: Detects function guards that check `length(x) < 2` (or
  `length(x) <= 1`) and rewrites them into two O(1) pattern-matched clauses.

  `length/1` traverses the entire list just to compare with a small number.
  When the guard is `length(x) < 2`, the intent is "zero or one element",
  which can be expressed with two pattern-matched clauses that are O(1).

  ## Bad

      def maximumdifference(list) when length(list) < 2, do: 0

  ## Good

      def maximumdifference([]), do: 0
      def maximumdifference([_]), do: 0

  Pattern matching is O(1) and idiomatic, while `length/1` is O(n).
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:def, meta, [{:when, _, [_call, guard]} | _rest]} = node, issues ->
          {node, find_length_less_than2(guard, meta, issues)}

        {:defp, meta, [{:when, _, [_call, guard]} | _rest]} = node, issues ->
          {node, find_length_less_than2(guard, meta, issues)}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)
    RuleHelpers.patches_from_ast_transform(ast, source, &transform_ast/1)
  end

  defp find_length_less_than2(guard_ast, def_meta, acc) do
    {_ast, issues} =
      Macro.prewalk(guard_ast, acc, fn
        # length(var) < 2
        {:<, meta, [{:length, _, [_var]}, n_node]} = node, issues ->
          if unwrap_int(n_node) == 2 do
            line = Keyword.get(meta, :line) || Keyword.get(def_meta, :line)
            {node, [build_issue(line) | issues]}
          else
            {node, issues}
          end

        # 2 > length(var) — reversed
        {:>, meta, [n_node, {:length, _, [_var]}]} = node, issues ->
          if unwrap_int(n_node) == 2 do
            line = Keyword.get(meta, :line) || Keyword.get(def_meta, :line)
            {node, [build_issue(line) | issues]}
          else
            {node, issues}
          end

        # length(var) <= 1
        {:<=, meta, [{:length, _, [_var]}, n_node]} = node, issues ->
          if unwrap_int(n_node) == 1 do
            line = Keyword.get(meta, :line) || Keyword.get(def_meta, :line)
            {node, [build_issue(line) | issues]}
          else
            {node, issues}
          end

        # 1 >= length(var) — reversed
        {:>=, meta, [n_node, {:length, _, [_var]}]} = node, issues ->
          if unwrap_int(n_node) == 1 do
            line = Keyword.get(meta, :line) || Keyword.get(def_meta, :line)
            {node, [build_issue(line) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    issues
  end

  defp unwrap_int({:__block__, _, [n]}) when is_integer(n), do: n
  defp unwrap_int(_), do: nil

  defp build_issue(line) do
    %Issue{
      rule: :avoid_length_guard_less_than2,
      message:
        "`length(x) < 2` in a guard traverses the entire list. " <>
          "Use pattern matching `[]` and `[_]` instead — both are O(1).",
      meta: %{line: line}
    }
  end

  # AST transform: walk and replace matching def/defp clauses
  defp transform_ast(ast) do
    Macro.prewalk(ast, fn
      {:def, meta, [{:when, when_meta, [call, guard]} | rest]} = node ->
        try_split_clause(:def, meta, when_meta, call, guard, rest, node)

      {:defp, meta, [{:when, when_meta, [call, guard]} | rest]} = node ->
        try_split_clause(:defp, meta, when_meta, call, guard, rest, node)

      node ->
        node
    end)
  end

  defp try_split_clause(kind, meta, _when_meta, call, guard, rest, original) do
    case extract_length_less_than2(guard) do
      {:ok, var} ->
        case replace_param_with_patterns(call, var) do
          {:ok, empty_call, single_call} ->
            # Return a list of two clauses (will be flattened by the block)
            {:__block__, [],
             [
               {kind, meta, [empty_call | rest]},
               {kind, meta, [single_call | rest]}
             ]}

          :error ->
            original
        end

      :error ->
        original
    end
  end

  # Extract the variable from length(var) < 2 or equivalent guards
  defp extract_length_less_than2({:<, _, [{:length, _, [var]}, n]}) do
    with {:ok, 2} <- extract_int(n),
         true <- simple_var?(var) do
      {:ok, var}
    else
      _ -> :error
    end
  end

  defp extract_length_less_than2({:>, _, [n, {:length, _, [var]}]}) do
    with {:ok, 2} <- extract_int(n),
         true <- simple_var?(var) do
      {:ok, var}
    else
      _ -> :error
    end
  end

  defp extract_length_less_than2({:<=, _, [{:length, _, [var]}, n]}) do
    with {:ok, 1} <- extract_int(n),
         true <- simple_var?(var) do
      {:ok, var}
    else
      _ -> :error
    end
  end

  defp extract_length_less_than2({:>=, _, [n, {:length, _, [var]}]}) do
    with {:ok, 1} <- extract_int(n),
         true <- simple_var?(var) do
      {:ok, var}
    else
      _ -> :error
    end
  end

  # Compound guard: left and right — extract from either side
  defp extract_length_less_than2({:and, _, [left, right]}) do
    case extract_length_less_than2(left) do
      {:ok, var} -> {:ok, var}
      :error -> extract_length_less_than2(right)
    end
  end

  defp extract_length_less_than2(_), do: :error

  defp extract_int({:__block__, _, [n]}) when is_integer(n), do: {:ok, n}
  defp extract_int(_), do: :error

  defp simple_var?({name, _, ctx}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)),
    do: true

  defp simple_var?(_), do: false

  # Replace the parameter `var` in the function call with patterns
  defp replace_param_with_patterns({func_name, func_meta, params}, var) do
    if Enum.any?(params, &same_var?(&1, var)) do
      empty_params =
        Enum.map(params, fn param ->
          if same_var?(param, var),
            do: {:__block__, [closing: [line: 0, column: 0]], [[]]},
            else: param
        end)

      single_params =
        Enum.map(params, fn param ->
          if same_var?(param, var),
            do: {:__block__, [], [[{:_, [], nil}]]},
            else: param
        end)

      {:ok, {func_name, func_meta, empty_params}, {func_name, func_meta, single_params}}
    else
      :error
    end
  end

  defp same_var?({name, _, _}, {name, _, _}) when is_atom(name), do: true
  defp same_var?(_, _), do: false
end
