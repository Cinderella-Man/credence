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

  ## Safe core — simple guards only

  Fires **only** when the *entire* guard is the length comparison. A compound
  guard (`when length(x) < 2 and P`, or `... or P`) is left untouched: splitting
  it into `[]`/`[_]` clauses would silently drop `P` and change behaviour. Those
  belong with the sibling `no_length_guard_to_pattern` (which preserves the
  remaining guard), not here.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {kind, meta, [{:when, _, [_call, guard]} | _rest]} = node, issues
        when kind in [:def, :defp] ->
          # Only a guard whose WHOLE expression is the length comparison is
          # rewritable: a compound guard (`length(x) < 2 and P`) cannot be split
          # into `[]`/`[_]` clauses without dropping `P`, so we leave it alone.
          case extract_length_less_than2(guard) do
            {:ok, _var} -> {node, [build_issue(Keyword.get(meta, :line)) | issues]}
            :error -> {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn
        {kind, _meta, [{:when, _, [call, guard]} | rest]} = node, acc
        when kind in [:def, :defp] ->
          case clause_patch(kind, call, guard, rest, node) do
            {:ok, patch} -> {node, [patch | acc]}
            :no -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(patches)
  end

  # Emit a single whole-clause patch holding the two replacement clauses, each
  # rendered SEPARATELY. Building one shared `{:__block__, ...}` of two clauses
  # and re-rendering the whole tree (the previous approach) made both clauses
  # claim the same Sourceror do/end positions, so `Sourceror.to_string`
  # mis-nested the bodies and dropped an `end` (the reverted bug).
  defp clause_patch(kind, call, guard, rest, node) do
    with {:ok, var} <- extract_length_less_than2(guard),
         {:ok, body, format} <- do_body(rest),
         {:ok, empty_call, single_call} <-
           replace_param_with_patterns(call, var, var_used?(body, var)) do
      separator = if format == :keyword, do: "\n", else: "\n\n"

      change =
        render_clause(kind, empty_call, body, format) <>
          separator <> render_clause(kind, single_call, body, format)

      {:ok, %{range: Sourceror.get_range(node), change: change}}
    else
      _ -> :no
    end
  end

  # Rebuild the clause with a FRESH `[do: body]` keyword. Reusing the original
  # Sourceror do-marker carries stale positions that make a multi-statement block
  # render as a `do:` one-liner (dropping statements). Only the plain `do:` body
  # is supported; anything else (rescue/after/…) bails so we never corrupt it.
  defp do_body([[{{:__block__, marker_meta, [:do]}, value}]]),
    do: {:ok, value, format_of(marker_meta)}

  defp do_body([[{:do, value}]]), do: {:ok, value, :block}

  defp do_body([{{:__block__, marker_meta, [:do]}, value}]),
    do: {:ok, value, format_of(marker_meta)}

  defp do_body([{:do, value}]), do: {:ok, value, :block}
  defp do_body(_), do: :error

  defp format_of(marker_meta) do
    if Keyword.get(marker_meta, :format) == :keyword, do: :keyword, else: :block
  end

  # Preserve the original `, do:` one-liner form vs `do ... end` block form.
  defp render_clause(kind, call, body, :keyword) do
    kw = [{{:__block__, [format: :keyword], [:do]}, strip_pos(body)}]
    Sourceror.to_string({kind, [], [call, kw]})
  end

  defp render_clause(kind, call, body, :block) do
    Sourceror.to_string({kind, [], [call, [do: strip_pos(body)]]})
  end

  # Drop stale source positions from the (re-used) body so it renders relative to
  # the freshly-built clause instead of its original far-away line numbers.
  defp strip_pos(ast) do
    Macro.prewalk(ast, fn
      {form, meta, args} when is_list(meta) ->
        {form, Keyword.drop(meta, [:line, :column, :newlines, :end_of_expression]), args}

      other ->
        other
    end)
  end

  defp build_issue(line) do
    %Issue{
      rule: :avoid_length_guard_less_than2,
      message:
        "`length(x) < 2` in a guard traverses the entire list. " <>
          "Use pattern matching `[]` and `[_]` instead — both are O(1).",
      meta: %{line: line}
    }
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

  # A compound guard (`length(x) < 2 and P`, `... or P`) is intentionally NOT
  # matched: splitting into `[]`/`[_]` clauses would drop the remaining
  # condition. Only a guard that is *exactly* the length comparison is fixable.
  defp extract_length_less_than2(_), do: :error

  defp extract_int({:__block__, _, [n]}) when is_integer(n), do: {:ok, n}
  defp extract_int(_), do: :error

  defp simple_var?({name, _, ctx}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)),
    do: true

  defp simple_var?(_), do: false

  # Replace the parameter `var` in the function call with the `[]` and `[_]`
  # patterns. When the body still references `var`, bind it (`[] = var`,
  # `[_] = var`) so the variable stays in scope — otherwise the split clauses
  # reference an unbound variable and fail to compile (the reverted bug). Fresh,
  # position-free pattern AST so each clause renders cleanly.
  defp replace_param_with_patterns({func_name, _func_meta, params}, var, bind?) do
    if Enum.any?(params, &same_var?(&1, var)) do
      empty = pattern_for([], var, bind?)
      single = pattern_for([{:_, [], nil}], var, bind?)

      empty_params = Enum.map(params, &if(same_var?(&1, var), do: empty, else: &1))
      single_params = Enum.map(params, &if(same_var?(&1, var), do: single, else: &1))

      {:ok, {func_name, [], empty_params}, {func_name, [], single_params}}
    else
      :error
    end
  end

  defp pattern_for(pattern, _var, false), do: pattern
  defp pattern_for(pattern, {name, _, _}, true), do: {:=, [], [pattern, {name, [], nil}]}

  # Does `body` reference the variable named like `var`?
  defp var_used?(body, {name, _, _}) do
    {_, used?} =
      Macro.prewalk(body, false, fn
        {^name, _, ctx} = n, _acc when is_atom(ctx) -> {n, true}
        n, acc -> {n, acc}
      end)

    used?
  end

  defp same_var?({name, _, _}, {name, _, _}) when is_atom(name), do: true
  defp same_var?(_, _), do: false
end
