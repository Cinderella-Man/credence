defmodule Credence.Pattern.NoManualFrequencies do
  @moduledoc """
  Readability rule: Detects manual frequency counting with
  `Enum.reduce(list, %{}, fn x, acc -> Map.update(acc, KEY, 1, &(&1 + 1)) end)`.

  When the counted key is the element itself, `Enum.frequencies/1` does exactly
  this in one call. When the key is a function of the element (e.g.
  `String.downcase(word)`), `Enum.frequencies_by/2` is the value-for-value
  equivalent — the key expression is carried over verbatim, so both forms produce
  byte-identical maps on every input (both available since Elixir 1.10).

  ## Bad

      list
      |> Enum.reduce(%{}, fn item, counts ->
        Map.update(counts, item, 1, &(&1 + 1))
      end)

      Enum.reduce(words, %{}, fn word, acc ->
        Map.update(acc, String.downcase(word), 1, &(&1 + 1))
      end)

  ## Good

      Enum.frequencies(list)

      Enum.frequencies_by(words, fn word -> String.downcase(word) end)
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
      # Piped: list |> Enum.reduce(%{}, fn ... end)
      {:|>, _,
       [
         list,
         {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [{:%{}, _, []}, body]}
       ]} = node ->
        rewrite(frequency_spec(body), list, node)

      # Direct: Enum.reduce(list, %{}, fn ... end)
      {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [list, {:%{}, _, []}, body]} = node ->
        rewrite(frequency_spec(body), list, node)

      node ->
        node
    end)
  end

  # Build the replacement call from the spec, or leave the node untouched.
  #   :identity              → Enum.frequencies(enum)
  #   {:derived, key, elem}  → Enum.frequencies_by(enum, fn elem -> key end)
  defp rewrite(:identity, enum, _node), do: enum_call(:frequencies, [enum])

  defp rewrite({:derived, key_ast, elem}, enum, _node) do
    key_fun = {:fn, [], [{:->, [], [[{elem, [], nil}], key_ast]}]}
    enum_call(:frequencies_by, [enum, key_fun])
  end

  defp rewrite(nil, _enum, node), do: node

  defp enum_call(fun, args) do
    {{:., [], [{:__aliases__, [], [:Enum]}, fun]}, [], args}
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

  defp frequency_fn?(body), do: frequency_spec(body) != nil

  # Classify a reduce fn into the kind of frequency rewrite it admits, or nil if
  # none is safe. The fn must be exactly
  #   fn elem, acc -> Map.update(acc, KEY, 1, &(&1 + 1)) end
  # — default 1, increment by exactly 1, `Map.update/4` against the accumulator.
  # Then:
  #   - KEY is the element itself        → :identity              (Enum.frequencies/1)
  #   - KEY is a function of the element → {:derived, KEY, elem}  (Enum.frequencies_by/2)
  #
  # Deliberately nil (no value-for-value rewrite exists):
  #   - weighted increments (`&(&1 + 2)`) — both frequency funcs count by 1;
  #   - non-1 default / non-empty initial map — not a from-scratch tally;
  #   - `Map.update!/3` — raises on the first (missing) key against a fresh `%{}`;
  #   - KEY that references the accumulator — can't be lifted into a key function
  #     that only receives the element (it would leave `acc` unbound).
  defp frequency_spec({:fn, _, [{:->, _, [params, fn_body]}]}) do
    # `var_name/1` returns `nil` for a non-variable param (a map/tuple pattern
    # like `%{block_number: number}`). `is_atom(nil)` is true, so guard against
    # `nil` explicitly — otherwise a destructuring element param slips through
    # and the fix emits `fn nil -> …` with the body vars unbound.
    with [elem_p, acc_p] <- params,
         elem when is_atom(elem) and not is_nil(elem) <- var_name(elem_p),
         acc when is_atom(acc) and not is_nil(acc) <- var_name(acc_p),
         {{:., _, [{:__aliases__, _, [:Map]}, :update]}, _, [acc_arg, key_arg, default, incr]} <-
           unwrap_block(fn_body),
         true <- var_name(acc_arg) == acc,
         true <- unwrap_literal(default) == 1,
         true <- increment_by_one?(incr) do
      cond do
        var_name(key_arg) == elem -> :identity
        references_var?(key_arg, acc) or calls_binding?(key_arg) -> nil
        true -> {:derived, key_arg, elem}
      end
    else
      _ -> nil
    end
  end

  defp frequency_spec(_), do: nil

  # Does `ast` reference the variable named `name` anywhere?
  defp references_var?(ast, name) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        node, true -> {node, true}
        {^name, _, ctx} = node, _ when is_atom(ctx) -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  # `binding/0` observes every variable in the current lexical scope, including
  # the accumulator even though its AST contains no explicit `acc` node.
  defp calls_binding?(ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        node, true -> {node, true}
        {:binding, _, []} = node, _ -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

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
          "can be replaced with `Enum.frequencies/1` (or `Enum.frequencies_by/2` when the " <>
          "key is derived from the element), which is clearer and optimized.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
