defmodule Credence.Pattern.PreferMapPutNew do
  @moduledoc """
  Performance and idiomatic code rule: detects an `if`/`unless` guard
  using `Map.has_key?/2` that only calls `Map.put/3` when the key is
  absent, and suggests `Map.put_new/3` instead.

  `Map.put_new/3` is implemented natively and expresses the intent
  directly — "put this key-value pair only if the key is missing."

  Only flags when:

  - The `if` condition is `Map.has_key?(map, key)` (or a single `!` negation)
  - The "key exists" branch returns `map` unchanged
  - The "key absent" branch calls `Map.put(map, key, value)`
  - Both branches reference the same `map` and `key`
  - `key` and `value` are **pure** (a bare variable or a scalar literal)

  ## Why the purity restriction

  `Map.put_new/3` always evaluates its `value` argument, whereas the
  `if`/`else` form evaluates `value` only when the key is absent. If `value`
  could raise or has a side effect, the rewrite would change behaviour when the
  key is present — so the rule fires only when `value` (and `key`, which the
  `if` form evaluates twice) is a variable or scalar literal that cannot raise
  or observe a side effect. Expressions like `Map.put(map, key, expensive())`
  are intentionally left alone (`Map.put_new_lazy/3` is the right tool there).

  ## Bad

      new_map =
        if Map.has_key?(map, key) do
          map
        else
          Map.put(map, key, value)
        end

      # negated condition with swapped branches:
      new_map =
        if !Map.has_key?(map, key) do
          Map.put(map, key, value)
        else
          map
        end

  ## Good

      new_map = Map.put_new(map, key, value)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:if, meta, [condition, branches]} = node, acc ->
          case detect_if(condition, branches) do
            {:ok, _map, _key, _val} ->
              {node, [build_issue(meta) | acc]}

            :none ->
              {node, acc}
          end

        {:unless, meta, [condition, branches]} = node, acc ->
          case detect_unless(condition, branches) do
            {:ok, _map, _key, _val} ->
              {node, [build_issue(meta) | acc]}

            :none ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, &apply_fix/1)
  end

  # Transform if-expression
  defp apply_fix({:if, _meta, [condition, branches]} = node) do
    case detect_if(condition, branches) do
      {:ok, map, key, val} -> build_put_new_call(map, key, val)
      :none -> node
    end
  end

  # Transform unless-expression
  defp apply_fix({:unless, _meta, [condition, branches]} = node) do
    case detect_unless(condition, branches) do
      {:ok, map, key, val} -> build_put_new_call(map, key, val)
      :none -> node
    end
  end

  defp apply_fix(node), do: node

  # Detects either:
  #   if Map.has_key?(map, key) do map else Map.put(map, key, val) end
  #   if !Map.has_key?(map, key) do Map.put(map, key, val) else map end
  #
  # The negation is matched at a SINGLE level only — `!!Map.has_key?` has even
  # parity (≡ no negation) and would mean "overwrite if present", which is NOT
  # `put_new`, so it must not match the negated branch.
  defp detect_if(condition, branches) do
    do_body = extract_branch_body(branches, :do)
    else_body = extract_branch_body(branches, :else)

    cond do
      # Standard: if has_key? → map, else → Map.put
      match?({:ok, _, _}, bare_has_key(condition)) ->
        {:ok, map, key} = bare_has_key(condition)

        if var_matches?(do_body, map) and safe_put?(else_body, map, key) do
          {:ok, map, key, extract_put_value(else_body)}
        else
          :none
        end

      # Single-negated: if !has_key? → Map.put, else → map
      match?({:ok, _, _}, negated_has_key(condition)) ->
        {:ok, map, key} = negated_has_key(condition)

        if safe_put?(do_body, map, key) and var_matches?(else_body, map) do
          {:ok, map, key, extract_put_value(do_body)}
        else
          :none
        end

      true ->
        :none
    end
  end

  # Detects: unless Map.has_key?(map, key) do Map.put(map, key, val) else map end
  # Only a bare (un-negated) condition — `unless !has_key?` ≡ `if has_key?`,
  # which is "overwrite if present", not `put_new`.
  defp detect_unless(condition, branches) do
    case bare_has_key(condition) do
      {:ok, map, key} ->
        do_body = extract_branch_body(branches, :do)
        else_body = extract_branch_body(branches, :else)

        if safe_put?(do_body, map, key) and var_matches?(else_body, map) do
          {:ok, map, key, extract_put_value(do_body)}
        else
          :none
        end

      :none ->
        :none
    end
  end

  # Matches exactly `Map.has_key?(map, key)` (no leading negation).
  defp bare_has_key(
         {{:., _, [{:__aliases__, _, [:Map]}, :has_key?]}, _, [map, key]}
       ),
       do: {:ok, map, key}

  defp bare_has_key(_), do: :none

  # Matches exactly `!Map.has_key?(map, key)` (a single negation).
  defp negated_has_key({:!, _, [inner]}), do: bare_has_key(inner)
  defp negated_has_key(_), do: :none

  # `Map.put(map, key, val)` against the same map/key, where key and value are
  # pure (a bare variable or a scalar literal). The purity requirement is what
  # makes `Map.put_new(map, key, val)` — which evaluates `val` eagerly and `key`
  # once — give the exact same answer as the lazy/double-eval `if` form.
  defp safe_put?(put_ast, map, key) do
    put_match?(put_ast, map, key) and pure?(key) and pure?(extract_put_value(put_ast))
  end

  # A term whose evaluation cannot raise or observe a side effect: a bare
  # variable reference or a scalar literal (number, atom, string).
  defp pure?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true

  defp pure?({:__block__, _, [literal]})
       when is_number(literal) or is_atom(literal) or is_binary(literal),
       do: true

  defp pure?(_), do: false

  # Checks if the AST is Map.put(same_map, same_key, _val)
  defp put_match?(
         {{:., _, [{:__aliases__, _, [:Map]}, :put]}, _, [put_map, put_key, _val]},
         map,
         key
       ) do
    ast_equal?(put_map, map) and ast_equal?(put_key, key)
  end

  defp put_match?(_, _, _), do: false

  # Extracts the value argument from Map.put(_, _, val)
  defp extract_put_value(
         {{:., _, [{:__aliases__, _, [:Map]}, :put]}, _, [_, _, val]}
       ),
       do: val

  # Checks if the AST is a plain variable reference matching target
  defp var_matches?({name_a, _, ctx_a}, {name_b, _, ctx_b})
       when is_atom(name_a) and is_atom(ctx_a) and is_atom(name_b) and is_atom(ctx_b),
       do: name_a == name_b

  defp var_matches?(_, _), do: false

  # Structural equality for AST nodes (ignoring metadata)
  defp ast_equal?({name, _, ctx_a}, {name, _, ctx_b})
       when is_atom(name) and is_atom(ctx_a) and is_atom(ctx_b),
       do: true

  defp ast_equal?(a, b), do: a == b

  # Sourceror wraps keyword keys in {:__block__, _, [:do]} / {:__block__, _, [:else]}
  defp extract_branch_body(branches, key) when is_list(branches) do
    Enum.find_value(branches, nil, fn
      {{:__block__, _, [^key]}, body} -> body
      _ -> nil
    end)
  end

  defp extract_branch_body(_, _), do: nil

  defp build_put_new_call(map, key, val) do
    # Map.put_new(map, key, val)
    {{:., [], [{:__aliases__, [], [:Map]}, :put_new]}, [], [map, key, val]}
  end

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_map_put_new,
      message:
        "`if Map.has_key?(map, key) do map else Map.put(map, key, val) end` " <>
          "can be replaced with `Map.put_new(map, key, val)` — it's more idiomatic " <>
          "and implemented natively.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
