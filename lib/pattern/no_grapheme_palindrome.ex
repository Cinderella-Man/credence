defmodule Credence.Pattern.NoGraphemePalindrome do
  @moduledoc """
  Readability & performance rule: Detects the pattern of decomposing a string
  into graphemes, only to compare it with its own `Enum.reverse`.

  This pattern creates an unnecessary intermediate list. Use `String.reverse/1`
  and compare strings directly instead.

  Only the `String.graphemes/1` form is handled — both it and `String.reverse/1`
  operate in grapheme space, so the rewrite is behaviour-identical for every
  input. The superficially similar `String.to_charlist/1` form is deliberately
  **not** rewritten: charlists index *codepoints*, while `String.reverse/1`
  reverses *graphemes*, and the two diverge on multi-codepoint graphemes
  (decomposed accents, ZWJ emoji, flags). See the codepoint↔grapheme policy in
  `CONTEXT.md`.

  ## What is flagged / fixed

  The fix shape depends on what the decomposed variable was built from and
  whether it is used anywhere besides the palindrome comparison:

    * built from a bare variable, used only in the comparison →
      the original string is inlined and the binding dropped:
      `g = String.graphemes(s); g == Enum.reverse(g)` → `s == String.reverse(s)`
    * built from a bare variable, but used elsewhere as a grapheme list →
      the comparison is inlined to `s == String.reverse(s)` while the
      `String.graphemes/1` binding is kept intact (so the other uses still see
      a list — rebinding it to the raw string would change their behaviour).
    * built from a larger expression (e.g. a pipe), used only in the
      comparison → the terminal `String.graphemes/1` is stripped from the
      binding and the comparison uses the variable:
      `g = s |> f() |> String.graphemes(); g == Enum.reverse(g)` →
      `g = s |> f(); g == String.reverse(g)` (inlining would duplicate `f`).
    * built from a larger expression *and* used elsewhere → not flagged: there
      is no behaviour-preserving single-expression rewrite.

  ## Bad

      graphemes = String.graphemes(s)
      graphemes == Enum.reverse(graphemes)

      normalized = s |> String.downcase() |> String.graphemes()
      normalized == Enum.reverse(normalized)

  ## Good

      s == String.reverse(s)

      normalized = s |> String.downcase()
      normalized == String.reverse(normalized)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    ast = annotate_function_scopes(ast)
    fixable = fixable_decompose_vars(ast)

    if map_size(fixable) == 0 do
      []
    else
      {_ast, issues} =
        Macro.prewalk(ast, [], fn
          {:==, meta, _} = node, acc ->
            case palindrome_var(node) do
              nil ->
                {node, acc}

              var ->
                if Map.has_key?(fixable, var),
                  do: {node, [build_issue(meta) | acc]},
                  else: {node, acc}
            end

          node, acc ->
            {node, acc}
        end)

      Enum.reverse(issues)
    end
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)
    ast = annotate_function_scopes(ast)
    fixable = fixable_decompose_vars(ast)

    if map_size(fixable) == 0 do
      []
    else
      RuleHelpers.patches_from_ast_transform(ast, source, fn input ->
        input
        |> rewrite_comparisons(fixable)
        |> rewrite_bindings(fixable)
      end)
    end
  end

  # --- comparison rewrite ---------------------------------------------------

  defp rewrite_comparisons(ast, fixable) do
    Macro.postwalk(ast, fn
      {:==, meta, [l, _r]} = node ->
        case palindrome_var(node) do
          nil ->
            node

          key ->
            case Map.fetch(fixable, key) do
              {:ok, {class, original}} -> rebuild_comparison(meta, l, key, class, original)
              :error -> node
            end
        end

      node ->
        node
    end)
  end

  # `:strip` keeps the variable and only swaps `Enum.reverse` → `String.reverse`.
  # `:inline` / `:keep_binding` substitute the original (bare) string on both
  # sides, so the comparison no longer depends on the decomposed variable.
  defp rebuild_comparison(meta, l, {_scope, var}, class, original) do
    operand =
      case class do
        :strip -> {var, [], nil}
        _ -> strip_layout_meta(original)
      end

    rev = string_reverse(operand)

    if match?({^var, _, nil}, l) do
      {:==, meta, [operand, rev]}
    else
      {:==, meta, [rev, operand]}
    end
  end

  defp string_reverse(arg) do
    {{:., [], [{:__aliases__, [], [:String]}, :reverse]}, [], [arg]}
  end

  # --- binding rewrite ------------------------------------------------------

  defp rewrite_bindings(ast, fixable) do
    Macro.postwalk(ast, fn
      {:__block__, meta, stmts} when is_list(stmts) ->
        {:__block__, meta, Enum.flat_map(stmts, &transform_binding(&1, fixable))}

      node ->
        node
    end)
  end

  defp transform_binding({:=, meta, [{var, _, nil} = lhs, rhs]} = stmt, fixable)
       when is_atom(var) do
    key = {Keyword.get(elem(lhs, 1), :credence_function_scope), var}

    case Map.fetch(fixable, key) do
      # Inlined and not needed anywhere else → drop the binding entirely.
      {:ok, {:inline, _original}} -> []
      # Inlined into the comparison, but still referenced as a list elsewhere →
      # keep the original `String.graphemes/1` binding untouched.
      {:ok, {:keep_binding, _original}} -> [stmt]
      # Strip the terminal `String.graphemes/1`, keep the variable.
      {:ok, {:strip, _original}} -> [{:=, meta, [lhs, strip_decomposition(rhs)]}]
      :error -> [stmt]
    end
  end

  defp transform_binding(stmt, _fixable), do: [stmt]

  # --- classification -------------------------------------------------------

  # Returns `%{var => {class, original_string_ast}}` for every decomposed
  # variable that has a behaviour-preserving fix. `class` is one of
  # `:inline`, `:keep_binding`, `:strip`.
  defp fixable_decompose_vars(ast) do
    ast
    |> collect_decompose_vars()
    |> Enum.flat_map(fn {key, original} ->
      case classify(ast, key, original) do
        :unfixable -> []
        class -> [{key, {class, original}}]
      end
    end)
    |> Map.new()
  end

  defp classify(ast, key, original) do
    comparisons = palindrome_comparison_count(ast, key)
    # Each palindrome comparison references the variable twice; the binding
    # references it once on its left-hand side. Anything beyond that is a use
    # we must not break.
    used_elsewhere? = var_ref_count(ast, key) - 1 - 2 * comparisons > 0
    bare? = match?({name, _, nil} when is_atom(name), original)

    cond do
      comparisons == 0 -> :unfixable
      bare? and not used_elsewhere? -> :inline
      bare? and used_elsewhere? -> :keep_binding
      not bare? and not used_elsewhere? -> :strip
      true -> :unfixable
    end
  end

  defp palindrome_comparison_count(ast, key) do
    {_ast, count} =
      Macro.prewalk(ast, 0, fn
        {:==, _, _} = node, acc -> {node, if(palindrome_var(node) == key, do: acc + 1, else: acc)}
        node, acc -> {node, acc}
      end)

    count
  end

  defp var_ref_count(ast, {scope, var}) do
    {_ast, count} =
      Macro.prewalk(ast, 0, fn
        {^var, meta, nil} = node, acc ->
          if Keyword.get(meta, :credence_function_scope) == scope,
            do: {node, acc + 1},
            else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    count
  end

  # Returns the variable in a `var == Enum.reverse(var)` comparison (either
  # operand order), or `nil` if the node is not such a comparison.
  defp palindrome_var({:==, _, [l, r]}), do: pal_var(l, r) || pal_var(r, l)
  defp palindrome_var(_node), do: nil

  defp pal_var(
         {var, meta, nil},
         {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, [{var, reverse_meta, nil}]}
       )
       when is_atom(var) do
    scope = Keyword.get(meta, :credence_function_scope)

    if Keyword.get(reverse_meta, :credence_function_scope) == scope,
      do: {scope, var},
      else: nil
  end

  defp pal_var(_left, _right), do: nil

  # --- shared helpers -------------------------------------------------------

  # Collects `%{var => stripped_rhs}` for variables bound (terminally) to
  # `String.graphemes/1`. Variables bound more than once are dropped so the
  # reference accounting in `classify/3` stays sound.
  defp collect_decompose_vars(ast) do
    {_ast, {vars, _seen}} =
      Macro.prewalk(ast, {%{}, MapSet.new()}, fn
        {:=, _, [{var, meta, nil}, rhs]} = node, {vars, seen} when is_atom(var) ->
          key = {Keyword.get(meta, :credence_function_scope), var}

          cond do
            MapSet.member?(seen, key) ->
              {node, {Map.delete(vars, key), seen}}

            decomposition_call?(rightmost(rhs)) ->
              {node, {Map.put(vars, key, strip_decomposition(rhs)), MapSet.put(seen, key)}}

            true ->
              {node, {vars, MapSet.put(seen, key)}}
          end

        node, acc ->
          {node, acc}
      end)

    vars
  end

  # Elixir variable metadata does not encode its enclosing function, so attach
  # a private traversal marker before correlating bindings and comparisons.
  defp annotate_function_scopes(ast) do
    {ast, _scope} =
      Macro.traverse(
        ast,
        [],
        fn
          {kind, _, _} = node, scopes when kind in [:def, :defp] ->
            {node, [System.unique_integer([:positive]) | scopes]}

          {var, meta, context}, [scope | _] = scopes
          when is_atom(var) and is_list(meta) and is_atom(context) ->
            {{var, Keyword.put(meta, :credence_function_scope, scope), context}, scopes}

          node, scopes ->
            {node, scopes}
        end,
        fn
          {kind, _, _} = node, [_scope | scopes] when kind in [:def, :defp] -> {node, scopes}
          node, scopes -> {node, scopes}
        end
      )

    ast
  end

  # Strip the terminal String.graphemes from an expression
  defp strip_decomposition(rhs) do
    case rhs do
      # Piped chain ending in decomposition: ... |> String.graphemes()
      {:|>, _, [rest, rhs_call]} ->
        if decomposition_call?(rhs_call), do: rest, else: rhs

      # Direct decomposition call: String.graphemes(s) → s
      {{:., _, [{:__aliases__, _, [:String]}, func]}, _, [arg]}
      when func == :graphemes ->
        arg

      _ ->
        rhs
    end
  end

  # Returns the rightmost (terminal) call in a pipe chain.
  defp rightmost({:|>, _, [_, right]}), do: rightmost(right)
  defp rightmost(other), do: other

  defp decomposition_call?(node) do
    match?(
      {{:., _, [{:__aliases__, _, [:String]}, func]}, _, _}
      when func == :graphemes,
      node
    )
  end

  # Drop layout metadata so a reused operand renders compactly in its new spot.
  defp strip_layout_meta(ast) do
    Macro.prewalk(ast, fn
      {form, meta, args} when is_list(meta) ->
        {form, Keyword.drop(meta, [:line, :column, :closing, :last, :end]), args}

      other ->
        other
    end)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_grapheme_palindrome,
      message:
        "Avoid decomposing a string into graphemes just to compare with `Enum.reverse/1`. " <>
          "Use `str == String.reverse(str)` instead — it is clearer and avoids creating an intermediate list.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
