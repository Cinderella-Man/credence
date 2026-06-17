defmodule Credence.Pattern.NoLengthGuardToPattern do
  @moduledoc """
  Refactoring rule: Detects guards that check list length with a literal
  comparison that can be replaced by a pattern match in the function head.

  Covers two forms:

  * `length(var) > 0` — non-empty check, replaceable with `[_ | _]`
  * `length(var) == N` for N in 1..5 — exact-size check, replaceable with
    `[_, _, ...]`

  Pattern matching is O(1) and idiomatic, while `length/1` traverses the
  entire list.

  ## Bad

      def process(list) when length(list) > 0 do
        Enum.sum(list)
      end

      defp triplet(list) when length(list) == 3 do
        List.to_tuple(list)
      end

  ## Good

      def process([_ | _] = list) do
        Enum.sum(list)
      end

      defp triplet([_, _, _] = list) do
        List.to_tuple(list)
      end
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {kind, meta, [{:when, _, [call, guard]} | _rest]} = node, issues
        when kind in [:def, :defp] ->
          {node, flag_if_fixable(call, guard, meta, issues)}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  # Flag only what the fix can actually rewrite: a `length(var) > 0` / `== N`
  # guard whose `var` is a top-level function parameter. Mirroring the fix
  # (`extract_fixable_check` + the param check in `replace_param`) keeps check and
  # fix in agreement, so the rule never flags a guard it would then no-op on
  # (e.g. a `length(x) == 1` on a variable captured deep inside a pattern).
  defp flag_if_fixable(call, guard, def_meta, acc) do
    with {:ok, var, pattern_kind, _remaining} <- extract_fixable_check(guard),
         true <- var_is_param?(call, var) do
      [build_issue(pattern_kind, Keyword.get(def_meta, :line)) | acc]
    else
      _ -> acc
    end
  end

  defp var_is_param?({_name, _meta, params}, var) when is_list(params),
    do: Enum.any?(params, &same_var?(&1, var))

  defp var_is_param?(_call, _var), do: false

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:def, meta, [{:when, when_meta, [call, guard]} | rest]} = node ->
        try_fix_def(:def, meta, when_meta, call, guard, rest, node)

      {:defp, meta, [{:when, when_meta, [call, guard]} | rest]} = node ->
        try_fix_def(:defp, meta, when_meta, call, guard, rest, node)

      node ->
        node
    end)
  end

  # Check helpers
  defp build_issue(:non_empty, line) do
    %Issue{
      rule: :no_length_guard_to_pattern,
      message:
        "`length(list) > 0` in a guard traverses the entire list. " <>
          "Use `[_ | _] = list` pattern matching instead — it is O(1).",
      meta: %{line: line}
    }
  end

  defp build_issue({:exact, n}, line) do
    underscores = List.duplicate("_", n) |> Enum.join(", ")

    %Issue{
      rule: :no_length_guard_to_pattern,
      message:
        "`length(list) == #{n}` in a guard traverses the entire list. " <>
          "Use `[#{underscores}] = list` pattern matching instead — it is O(1).",
      meta: %{line: line}
    }
  end

  # Fix helpers
  defp try_fix_def(kind, meta, when_meta, call, guard, rest, original) do
    case extract_fixable_check(guard) do
      {:ok, var, pattern_kind, remaining_guard} ->
        pattern = build_match_pattern(pattern_kind)

        case replace_param(call, var, pattern) do
          {:ok, new_call} ->
            case remaining_guard do
              nil -> {kind, meta, [new_call | rest]}
              other -> {kind, meta, [{:when, when_meta, [new_call, other]} | rest]}
            end

          :error ->
            original
        end

      :error ->
        original
    end
  end

  # length(var) > 0
  defp extract_fixable_check({:>, _, [{:length, _, [var]}, zero]}) do
    with {:ok, 0} <- extract_int(zero),
         true <- simple_var?(var) do
      {:ok, var, :non_empty, nil}
    else
      _ -> :error
    end
  end

  # length(var) == N (1..5)
  defp extract_fixable_check({:==, _, [{:length, _, [var]}, n_ast]}) do
    with {:ok, n} <- extract_int(n_ast),
         true <- n >= 1 and n <= 5,
         true <- simple_var?(var) do
      {:ok, var, {:exact, n}, nil}
    else
      _ -> :error
    end
  end

  # Compound guard: left and right — extract from either side
  defp extract_fixable_check({:and, _, [left, right]}) do
    case extract_fixable_check(left) do
      {:ok, var, kind, nil} ->
        {:ok, var, kind, right}

      _ ->
        case extract_fixable_check(right) do
          {:ok, var, kind, nil} -> {:ok, var, kind, left}
          _ -> :error
        end
    end
  end

  defp extract_fixable_check(_), do: :error
  defp extract_int({:__block__, _, [n]}) when is_integer(n), do: {:ok, n}
  defp extract_int(_), do: :error

  defp simple_var?({name, _, ctx}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)),
    do: true

  defp simple_var?(_), do: false

  defp same_var?({name, _, _}, {name, _, _}) when is_atom(name), do: true
  defp same_var?(_, _), do: false

  defp replace_param({func_name, func_meta, params}, var, pattern) do
    if Enum.any?(params, &same_var?(&1, var)) do
      new_params =
        Enum.map(params, fn param ->
          if same_var?(param, var), do: {:=, [], [pattern, param]}, else: param
        end)

      {:ok, {func_name, func_meta, new_params}}
    else
      :error
    end
  end

  # [_ | _]
  defp build_match_pattern(:non_empty) do
    [{:|, [], [{:_, [], nil}, {:_, [], nil}]}]
  end

  # [_, _, ...] with exactly n underscores
  defp build_match_pattern({:exact, n}) do
    List.duplicate({:_, [], nil}, n)
  end
end
