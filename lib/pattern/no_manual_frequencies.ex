defmodule Credence.Pattern.NoManualFrequencies do
  @moduledoc """
  Readability rule: Detects manual frequency counting with
  `Enum.reduce(list, %{}, fn x, acc -> Map.update(acc, x, 1, ...) end)`.

  `Enum.frequencies/1` (available since Elixir 1.10) does exactly this in a
  single, optimized call.

  ## Bad

      list
      |> Enum.reduce(%{}, fn item, counts ->
        Map.update(counts, item, 1, &(&1 + 1))
      end)

  ## Good

      Enum.frequencies(list)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Direct: Enum.reduce(list, %{}, fn ... -> Map.update(...) end)
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [_list, {:%{}, _, []}, body]} =
            node,
        issues ->
          if frequency_fn?(body) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        # Piped: list |> Enum.reduce(%{}, fn ... -> Map.update(...) end)
        {:|>, meta,
         [
           _,
           {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [{:%{}, _, []}, body]}
         ]} = node,
        issues ->
          if frequency_fn?(body) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      # Piped: list |> Enum.reduce(%{}, fn ... end) → Enum.frequencies(list)
      {:|>, _,
       [
         list,
         {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [{:%{}, _, []}, body]}
       ]} = node ->
        if frequency_fn?(body) do
          enum_frequencies_call(list)
        else
          node
        end

      # Direct: Enum.reduce(list, %{}, fn ... end) → Enum.frequencies(list)
      {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [list, {:%{}, _, []}, body]} = node ->
        if frequency_fn?(body) do
          enum_frequencies_call(list)
        else
          node
        end

      node ->
        node
    end)
  end

  defp enum_frequencies_call(enum) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :frequencies]}, [], [enum]}
  end

  # Sourceror wraps literals in {:__block__, _, [value]}
  defp unwrap_literal({:__block__, _, [val]}), do: val
  defp unwrap_literal(val), do: val

  defp unwrap_block({:__block__, _, [single]}), do: single
  defp unwrap_block(other), do: other

  # The bare variable name of an AST node, or nil if it isn't a plain var.
  # A var is `{name, meta, context}` with an atom context (nil counts); a call
  # is `{name, meta, args}` with a LIST as the third element — that returns nil.
  defp var_name({:__block__, _, [inner]}), do: var_name(inner)
  defp var_name({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: name
  defp var_name(_), do: nil

  # The safe core of a frequency reduce: the fn must be exactly
  #   fn elem, acc -> Map.update(acc, elem, 1, &(&1 + 1)) end
  # i.e. the counted KEY is the element itself (not a derived expression like
  # `String.downcase(word)` — that would count different buckets), the default
  # is 1, and the update increments by exactly 1. Only then is the reduce
  # value-for-value identical to `Enum.frequencies(enum)`.
  #
  # Deliberately NOT matched (no safe same-answer rewrite to Enum.frequencies):
  #   - derived keys (`Map.update(acc, f(elem), ...)`) — different buckets;
  #   - weighted increments (`&(&1 + 2)`) — Enum.frequencies always counts by 1;
  #   - `Map.update!/3` — raises on the first (missing) key, so it never equals
  #     a fresh-`%{}` reduce on any non-empty input.
  defp frequency_fn?({:fn, _, [{:->, _, [params, fn_body]}]}) do
    with [elem_p, acc_p] <- params,
         elem when is_atom(elem) <- var_name(elem_p),
         acc when is_atom(acc) <- var_name(acc_p),
         {{:., _, [{:__aliases__, _, [:Map]}, :update]}, _, [acc_arg, key_arg, default, incr]} <-
           unwrap_block(fn_body) do
      var_name(acc_arg) == acc and var_name(key_arg) == elem and
        unwrap_literal(default) == 1 and increment_by_one?(incr)
    else
      _ -> false
    end
  end

  defp frequency_fn?(_), do: false

  # `&(&1 + 1)` / `&(1 + &1)` or `fn n -> n + 1 end` / `fn n -> 1 + n end`.
  defp increment_by_one?({:&, _, [expr]}), do: plus_one?(expr, &capture_one?/1)

  defp increment_by_one?({:fn, _, [{:->, _, [[p], fn_body]}]}) do
    case var_name(p) do
      nil -> false
      name -> plus_one?(unwrap_block(fn_body), &(var_name(&1) == name))
    end
  end

  defp increment_by_one?(_), do: false

  defp plus_one?({:+, _, [a, b]}, operand?) do
    (operand?.(a) and unwrap_literal(b) == 1) or (unwrap_literal(a) == 1 and operand?.(b))
  end

  defp plus_one?(_, _), do: false

  defp capture_one?({:&, _, [n]}), do: unwrap_literal(n) == 1
  defp capture_one?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :no_manual_frequencies,
      message:
        "Manual frequency counting with `Enum.reduce/3` + `Map.update/4` and an empty map " <>
          "can be replaced with `Enum.frequencies/1`, which is clearer and optimized.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
