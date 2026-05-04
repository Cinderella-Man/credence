defmodule Credence.Rule.NoLengthGuardToPattern do
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
  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:def, meta, [{:when, _, [_call, guard]} | _rest]} = node, issues ->
          {node, find_fixable_length(guard, meta, issues)}

        {:defp, meta, [{:when, _, [_call, guard]} | _rest]} = node, issues ->
          {node, find_fixable_length(guard, meta, issues)}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      {:def, meta, [{:when, when_meta, [call, guard]} | rest]} = node ->
        try_fix_def(:def, meta, when_meta, call, guard, rest, node)

      {:defp, meta, [{:when, when_meta, [call, guard]} | rest]} = node ->
        try_fix_def(:defp, meta, when_meta, call, guard, rest, node)

      node ->
        node
    end)
    |> Sourceror.to_string()
  end

  # ---------------------------------------------------------------------------
  # Check helpers
  # ---------------------------------------------------------------------------

  defp find_fixable_length(guard_ast, def_meta, acc) do
    {_ast, issues} =
      Macro.prewalk(guard_ast, acc, fn
        # length(var) > 0
        {:>, meta, [{:length, _, [_var]}, 0]} = node, issues ->
          line = Keyword.get(meta, :line) || Keyword.get(def_meta, :line)
          {node, [build_issue(:non_empty, line) | issues]}

        # length(var) == N where N in 1..5
        {:==, meta, [{:length, _, [_var]}, n]} = node, issues
        when is_integer(n) and n >= 1 and n <= 5 ->
          line = Keyword.get(meta, :line) || Keyword.get(def_meta, :line)
          {node, [build_issue({:exact, n}, line) | issues]}

        node, issues ->
          {node, issues}
      end)

    issues
  end

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

  # ---------------------------------------------------------------------------
  # Fix helpers
  # ---------------------------------------------------------------------------

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

  # --- Guard extraction (Sourceror AST: integers may be __block__-wrapped) ---

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
      {:ok, var, kind, nil} -> {:ok, var, kind, right}
      _ ->
        case extract_fixable_check(right) do
          {:ok, var, kind, nil} -> {:ok, var, kind, left}
          _ -> :error
        end
    end
  end

  defp extract_fixable_check(_), do: :error

  # --- Integer extraction (handles Sourceror's __block__ wrapper) ---

  defp extract_int({:__block__, _, [n]}) when is_integer(n), do: {:ok, n}
  defp extract_int(n) when is_integer(n), do: {:ok, n}
  defp extract_int(_), do: :error

  # --- Variable helpers ---

  defp simple_var?({name, _, ctx}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)),
    do: true

  defp simple_var?(_), do: false

  defp same_var?({name, _, _}, {name, _, _}) when is_atom(name), do: true
  defp same_var?(_, _), do: false

  # --- Parameter replacement ---

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

  # --- Pattern builders ---

  # [_ | _]
  defp build_match_pattern(:non_empty) do
    [{:|, [], [{:_, [], nil}, {:_, [], nil}]}]
  end

  # [_, _, ...] with exactly n underscores
  defp build_match_pattern({:exact, n}) do
    List.duplicate({:_, [], nil}, n)
  end
end
