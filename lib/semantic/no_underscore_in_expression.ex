defmodule Credence.Semantic.NoUnderscoreInExpression do
  @moduledoc """
  Fixes compiler errors caused by using `_` in expression position,
  such as a tuple key in a for-comprehension body or a comparison
  against a tuple containing wildcards.

  The Elixir compiler rejects `_` in expression position:

      for _ <- 0..(n - 1), into: %{} do
        {_, :infinity}    # ← error: invalid use of _
      end

  The fix renames the `_` generator to a fresh variable (`idx`)
  and updates all references in the comprehension body:

      for idx <- 0..(n - 1), into: %{} do
        {idx, :infinity}
      end

  A second common pattern is comparing a value against a tuple
  containing wildcards:

      s == {:busy, _}    # ← error: invalid use of _

  The fix converts this to a `match?` call where `_` is in
  pattern position:

      match?({:busy, _}, s)

  This half is deliberately narrow. It only fires when every
  non-`_` element of the tuple is a plain literal (atom, number,
  string), and never inside a guard or a `quote` block — see
  `convertible_tuple?/1` and `walk/2` for why.

  ## Bad

      defmodule M do
        def f(s) do
          s == {"busy", _}
        end
      end

  ## Good

      defmodule M do
        def f(s) do
          match?({"busy", _}, s)
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, "invalid use of _")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_underscore_in_expression,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    case parse(source) do
      {:ok, ast} ->
        transformed = transform_underscores(ast)

        if transformed == ast do
          source
        else
          patches = Credence.RuleHelpers.patches_from_diff(ast, transformed)

          case patches do
            [] -> source
            _ -> Sourceror.patch_string(source, patches)
          end
        end

      :error ->
        source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line

  defp parse(source) do
    {:ok, Sourceror.parse_string!(source)}
  rescue
    _ -> :error
  end

  # Forms that introduce a *pattern* or a new binding/scope. If any of these
  # appear in the comprehension body we refuse to fix: a blind rename would
  # rewrite `_` that sit in pattern position (e.g. `{_, _} = a`, a `case`
  # wildcard, an `fn` arg), silently changing match semantics or shadowing a
  # binding. Inside a body free of all of these, every `_` is unambiguously in
  # expression position — exactly the invalid use the compiler rejects — so
  # renaming all of them to one fresh variable is the same-answer fix.
  @pattern_forms [
    :=,
    :case,
    :cond,
    :with,
    :for,
    :fn,
    :receive,
    :try,
    :&,
    :quote,
    :unquote,
    :<-,
    :->,
    :^
  ]

  # Forms whose children must not get the `==` -> `match?` rewrite:
  #
  #   * `when` — `match?/2` expands to a `case`, which is not allowed in a
  #     guard, so rewriting `def f(s) when s == {:busy, _}` would swap one
  #     compile error for another.
  #   * `quote` — inside quoted code `s == {:busy, _}` is *valid*; it just
  #     builds AST. Rewriting it would silently change what the macro emits.
  @no_eq_rewrite_forms [:when, :quote]

  defp transform_underscores(ast), do: walk(ast, true)

  # A postwalk (children first, then the node) that additionally threads an
  # `eq_ok?` flag down the tree so we can switch the `==` half off in the
  # contexts listed above. The `for` half is unaffected by the flag.
  defp walk({form, meta, args}, eq_ok?) when is_list(args) do
    child_ok? = eq_ok? and form not in @no_eq_rewrite_forms

    {walk(form, child_ok?), meta, Enum.map(args, &walk(&1, child_ok?))}
    |> visit(eq_ok?)
  end

  defp walk({left, right}, eq_ok?), do: {walk(left, eq_ok?), walk(right, eq_ok?)}
  defp walk(list, eq_ok?) when is_list(list), do: Enum.map(list, &walk(&1, eq_ok?))
  defp walk(other, _eq_ok?), do: other

  # Existing: for comprehension with underscore generator.
  defp visit({:for, meta, args} = node, _eq_ok?) when is_list(args) do
    if fixable?(args) do
      fresh = fresh_var_name(args)
      {:for, meta, rename_underscore_in_for_args(args, fresh)}
    else
      node
    end
  end

  # New: == comparison where one side is a tuple literal containing `_`.
  # Convert `value == {:atom, _}` to `match?({:atom, _}, value)`.
  defp visit({:==, eq_meta, [left, right]} = node, true) do
    cond do
      convertible_tuple?(right) and not deep_contains_underscore?(left) ->
        {:match?, eq_meta, [right, left]}

      convertible_tuple?(left) and not deep_contains_underscore?(right) ->
        {:match?, eq_meta, [left, right]}

      true ->
        node
    end
  end

  defp visit(node, _eq_ok?), do: node

  # Safe to fix only when there is exactly one `_` generator (so a body `_`
  # maps to it unambiguously) and the body uses `_` solely in expression
  # position.
  defp fixable?(args) do
    underscore_generator_count(args) == 1 and fixable_body?(args)
  end

  defp underscore_generator_count(args) when is_list(args) do
    Enum.count(args, fn
      {:<-, _, [{:_, _, nil}, _]} -> true
      _ -> false
    end)
  end

  defp fixable_body?(args) do
    case do_body(args) do
      {:ok, body} -> contains_underscore?(body) and not contains_pattern_form?(body)
      :error -> false
    end
  end

  defp do_body(args) do
    Enum.find_value(args, :error, fn
      [{{:__block__, _, [:do]}, body}] -> {:ok, body}
      _ -> false
    end)
  end

  defp contains_underscore?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:_, _, ctx} = n, _acc when is_atom(ctx) -> {n, true}
        n, acc -> {n, acc}
      end)

    found
  end

  defp contains_pattern_form?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {head, _, _} = n, _acc when head in @pattern_forms -> {n, true}
        n, acc -> {n, acc}
      end)

    found
  end

  # True when `node` is a tuple literal (2-tuple or n-tuple) that contains at
  # least one `_` wildcard *and* whose every other element is a plain literal.
  # Covers the common LLM pattern `value == {:busy, _}`.
  #
  # The literal-only requirement is what makes the rewrite safe. On the `==`
  # side a bare variable is a *read*; in the `match?/2` pattern the same
  # variable is a fresh *binding* that matches anything, so `s == {a, _}` would
  # become `match?({a, _}, s)` — true for every 2-tuple, silently wrong rather
  # than merely uncompilable. Calls (`s == {f(x), _}`) are not valid in a
  # pattern at all and would just swap one compile error for another.
  defp convertible_tuple?({:__block__, _, [inner]}), do: convertible_tuple?(inner)

  defp convertible_tuple?({left, right}), do: convertible_elements?([left, right])

  defp convertible_tuple?({:{}, _, args}) when is_list(args), do: convertible_elements?(args)

  defp convertible_tuple?(_), do: false

  defp convertible_elements?(elements) do
    Enum.any?(elements, &wildcard?/1) and Enum.all?(elements, &pattern_safe_element?/1)
  end

  defp wildcard?({:_, _, ctx}) when is_atom(ctx), do: true
  defp wildcard?(_), do: false

  defp pattern_safe_element?({:_, _, ctx}) when is_atom(ctx), do: true

  defp pattern_safe_element?({:__block__, _, [literal]})
       when is_atom(literal) or is_number(literal) or is_binary(literal),
       do: true

  defp pattern_safe_element?(_), do: false

  # Recurse into 2-tuples (which Macro.prewalk treats as leaves) so we can
  # detect `_` anywhere inside a value-side expression.
  defp deep_contains_underscore?({:_, _, ctx}) when is_atom(ctx), do: true

  defp deep_contains_underscore?({left, right}),
    do: deep_contains_underscore?(left) or deep_contains_underscore?(right)

  defp deep_contains_underscore?({_, _, args}) when is_list(args),
    do: Enum.any?(args, &deep_contains_underscore?/1)

  defp deep_contains_underscore?(_), do: false

  # A variable name not used anywhere in the comprehension, so the renamed
  # generator cannot collide with (or shadow) anything the body references.
  defp fresh_var_name(args) do
    used = collect_var_names(args)
    candidates = [:idx, :i, :index] ++ Enum.map(0..999, &:"idx_#{&1}")
    Enum.find(candidates, :idx, fn name -> not MapSet.member?(used, name) end)
  end

  defp collect_var_names(ast) do
    {_, names} =
      Macro.prewalk(ast, MapSet.new(), fn
        {name, _, ctx} = n, acc when is_atom(name) and is_atom(ctx) ->
          {n, MapSet.put(acc, name)}

        n, acc ->
          {n, acc}
      end)

    names
  end

  defp rename_underscore_in_for_args(args, fresh) do
    Enum.map(args, fn
      {:<-, arrow_meta, [{:_, var_meta, nil}, range]} ->
        {:<-, arrow_meta, [{fresh, var_meta, nil}, range]}

      [{{:__block__, do_meta, [:do]}, body}] ->
        new_body =
          Macro.prewalk(body, fn
            {:_, u_meta, nil} -> {fresh, u_meta, nil}
            other -> other
          end)

        [{{:__block__, do_meta, [:do]}, new_body}]

      other ->
        other
    end)
  end
end
