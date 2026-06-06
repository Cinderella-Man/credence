defmodule Credence.Pattern.NoRepeatedDivRem do
  @moduledoc """
  Detects a `div/2` or `rem/2` result that is **already bound to a variable**
  by an anchor statement and then re-computed verbatim later in the same
  function clause body, and rewrites the later occurrences to read the bound
  variable instead.

  ## Bad

      defp check(x) do
        a = rem(x, 2)
        b = rem(x, 2)
        {a, b}
      end

  ## Good

      defp check(x) do
        a = rem(x, 2)
        b = a
        {a, b}
      end

  ## Why so narrow

  Generic common-subexpression elimination for `div`/`rem` is **not**
  behaviour-preserving: it has to invent a variable name, find an insertion
  point that dominates every use, and prove the arguments are stable and
  side-effect-free. Getting any of those wrong changes the answer. This rule
  fires only on the one shape it can prove safe:

    * The **first** (source-earliest) occurrence of the repeated call is a
      top-level statement of the body block of the form `lhs = div(a, b)` /
      `lhs = rem(a, b)` — the *anchor*. The anchor's evaluation (and any
      `ArithmeticError` it would raise) therefore happens exactly where it
      did before; later occurrences are only reached, in the original, after
      the anchor already succeeded.

    * Every argument is a **bare variable or a numeric literal** — never a
      call — so the call has no side effects and re-running it fewer times is
      unobservable.

    * No argument variable, and `lhs` itself, is **bound anywhere** in the
      body (`=`, `<-`, or a `->`/`fn` clause head). That rules out rebinding
      and shadowing, so the value bound by the anchor equals what each later
      occurrence would compute, and `lhs` is in scope (and unchanged) at every
      later occurrence — including inside closures, which capture it.

  Under those conditions each later `op(a, b)` is replaced by `lhs`. Anything
  outside this shape (the first occurrence is a sub-expression, not a clean
  binding; a non-trivial argument; a rebound variable) is deliberately left
  untouched.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @ops [:div, :rem]
  @special_forms [:__MODULE__, :__DIR__, :__ENV__, :__CALLER__, :__STACKTRACE__, :__block__]

  @impl true
  def check(ast, _opts) do
    ast
    |> def_bodies()
    |> Enum.flat_map(&fixable_groups/1)
    |> Enum.map(fn group ->
      %Issue{
        rule: :no_repeated_div_rem,
        message:
          "`#{group.call_str}` is already bound to `#{group.lhs}` and recomputed " <>
            "later in the same scope. Reuse `#{group.lhs}` instead.",
        meta: %{line: group.line}
      }
    end)
  end

  @impl true
  def fix_patches(ast, _opts) do
    ast
    |> def_bodies()
    |> Enum.flat_map(&fixable_groups/1)
    |> Enum.flat_map(fn group ->
      Enum.map(group.others, fn {_node, range} ->
        %{range: range, change: Atom.to_string(group.lhs)}
      end)
    end)
  end

  # --- def/defp body discovery ---

  defp def_bodies(ast) do
    {_ast, bodies} =
      Macro.prewalk(ast, [], fn
        {kind, _meta, [_head, body_kw]} = node, acc
        when kind in [:def, :defp] and is_list(body_kw) ->
          case do_body(body_kw) do
            {:ok, body} -> {node, [body | acc]}
            :error -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(bodies)
  end

  defp do_body(body_kw) do
    Enum.find_value(body_kw, :error, fn
      {{:__block__, _, [:do]}, body} -> {:ok, body}
      _ -> nil
    end)
  end

  # --- the safe core ---

  defp fixable_groups({:__block__, _meta, stmts} = body)
       when is_list(stmts) and length(stmts) >= 2 do
    bound = bound_vars(body)

    Enum.flat_map(stmts, fn
      {:=, _, [lhs, {op, _, [_, _] = args} = call]} when op in @ops ->
        case anchor_group(body, bound, lhs, op, args, call) do
          {:ok, group} -> [group]
          :error -> []
        end

      _ ->
        []
    end)
  end

  defp fixable_groups(_), do: []

  defp anchor_group(body, bound, lhs, op, args, call) do
    with {:ok, lname} <- simple_var(lhs),
         true <- args_simple?(args),
         vars = arg_vars(args),
         true <- lname not in vars,
         true <- count(bound, lname) == 1,
         true <- Enum.all?(vars, fn v -> count(bound, v) == 0 end),
         %Sourceror.Range{} = anchor_range <- Sourceror.get_range(call),
         {:ok, occ} <- occurrences(body, op, args),
         [{_, first_range} | _] when length(occ) >= 2 <- occ,
         true <- first_range == anchor_range do
      others = Enum.reject(occ, fn {_n, r} -> r == anchor_range end)

      {:ok,
       %{
         lhs: lname,
         call_str: Macro.to_string(call),
         line: anchor_range.start[:line],
         others: others
       }}
    else
      _ -> :error
    end
  end

  # All occurrences of `op` whose arguments match `args` structurally,
  # sorted by source position. Returns `:error` if any matching node lacks
  # a resolvable range (so we never silently drop an occurrence we can't
  # account for).
  defp occurrences(body, op, args) do
    target = strip_meta(args)

    {_b, acc} =
      Macro.prewalk(body, [], fn
        {^op, _m, [_, _] = oargs} = node, acc ->
          if strip_meta(oargs) == target do
            {node, [{node, Sourceror.get_range(node)} | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    if Enum.any?(acc, fn {_n, r} -> not match?(%Sourceror.Range{}, r) end) do
      :error
    else
      {:ok, Enum.sort_by(acc, fn {_n, r} -> {r.start[:line], r.start[:column]} end)}
    end
  end

  # --- argument / variable predicates ---

  defp simple_var({name, _, ctx}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) do
    if proper_var?(name), do: {:ok, name}, else: :error
  end

  defp simple_var(_), do: :error

  defp args_simple?(args), do: Enum.all?(args, &simple_arg?/1)

  defp simple_arg?({:__block__, _, [v]}) when is_integer(v) or is_float(v), do: true

  defp simple_arg?({name, _, ctx}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)),
    do: proper_var?(name)

  defp simple_arg?(_), do: false

  defp arg_vars(args) do
    Enum.flat_map(args, fn
      {name, _, ctx} when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) ->
        if proper_var?(name), do: [name], else: []

      _ ->
        []
    end)
  end

  # A normal, readable variable name: not a literal-block (`__block__`),
  # not a special form, not an underscore-prefixed (write-only) name.
  defp proper_var?(name) do
    s = Atom.to_string(name)
    not String.starts_with?(s, "_") and name not in @special_forms
  end

  # --- bound-variable collection (sound over-approximation) ---
  #
  # Every name introduced by a binding construct anywhere in the body, with
  # multiplicity. We over-collect (e.g. pinned `^x` and guard variables count
  # as "bound"): that only ever rejects more cases, never admits an unsafe
  # one. The constructs that bind: `=`, `<-` (for/with generators), and
  # `->` clause heads (fn/case/cond/with/receive/try/for-reduce).
  defp bound_vars(body) do
    {_b, acc} =
      Macro.prewalk(body, [], fn
        {:=, _, [pattern, _]} = node, acc -> {node, pattern_vars(pattern) ++ acc}
        {:<-, _, [pattern, _]} = node, acc -> {node, pattern_vars(pattern) ++ acc}
        {:->, _, [params, _]} = node, acc -> {node, pattern_vars(params) ++ acc}
        node, acc -> {node, acc}
      end)

    acc
  end

  defp pattern_vars(pattern) do
    {_p, acc} =
      Macro.prewalk(pattern, [], fn
        {name, _, ctx} = node, acc when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) ->
          if proper_var?(name), do: {node, [name | acc]}, else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  defp count(list, x), do: Enum.count(list, &(&1 == x))

  defp strip_meta(ast) do
    Macro.prewalk(ast, fn
      {form, meta, args} when is_list(meta) -> {form, [], args}
      other -> other
    end)
  end
end
