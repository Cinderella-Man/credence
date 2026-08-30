defmodule Credence.Semantic.PreferKernelMaxOverLocal do
  @moduledoc """
  Removes a local `defp max/2`/`defp min/2` that *exactly* re-implements the
  auto-imported `Kernel.max/2`/`Kernel.min/2`.

  LLMs frequently define a private `max/2` with two guard clauses
  (`when a >= b` / `when b > a`) even though `Kernel.max/2` is auto-imported and
  already provides this exact behaviour. The compiler then errors because the
  local definition shadows the imported `Kernel.max/2`:

      imported Kernel.max/2 conflicts with local function

  ## Why this is narrowed to the canonical body

  The diagnostic fires for **any** local `max/2` — including one that does
  something completely different (`defp max(a, b), do: a * b`). Deleting that
  body and redirecting callers to `Kernel.max/2` would silently change the
  answer. A behaviour-preserving fix is only possible when the local function is
  provably the same function as the `Kernel` builtin.

  So this rule only removes the local clauses when they are the exact canonical
  reimplementation:

      defp max(a, b) when a >= b, do: a
      defp max(a, b) when b > a, do: b

  (and the `<=`/`<` symmetric form for `min`). The `>=`/`<=` clause must return
  the *first* parameter so the tie case agrees with `Kernel` for distinct-but-
  equal terms (e.g. `max(1, 1.0)` returns `1`, not `1.0`). Anything else —
  a different body, another arity sharing the name, a `&max/2` capture, or a
  piped `x |> max(y)` we can't safely requalify — is left untouched.

  ## Bad

      defmodule SolutionPKMOL do
        def calculate do
          max(3, 5)
        end

        defp max(a, b) when a >= b, do: a
        defp max(a, b) when b > a, do: b
      end

  ## Good

      defmodule SolutionPKMOL do
        def calculate do
          Kernel.max(3, 5)
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  # For each supported function: the tie-inclusive op (and its flip) that must
  # return the FIRST parameter, and the strict op (and its flip) that must
  # return the SECOND parameter. Together the two clauses are total and identical
  # to the `Kernel` builtin.
  @configs %{
    max: %{eq: :>=, eq_flip: :<=, st: :>, st_flip: :<},
    min: %{eq: :<=, eq_flip: :>=, st: :<, st_flip: :>}
  }

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    Regex.match?(~r{imported Kernel\.(?:max|min)/2 conflicts with local function}, msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    label =
      case extract_conflicting_func(diagnostic) do
        nil -> "function"
        name -> "#{name}/2"
      end

    %Issue{
      rule: :prefer_kernel_max_over_local,
      message: "Local #{label} reimplements Kernel.#{label} — use the built-in",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    with name when name != nil <- extract_conflicting_func(diagnostic),
         {:ok, ast} <- parse(source),
         defps <- defps_named(ast, name),
         true <- canonical_pair?(name, defps) do
      removed = remove_defp_arity2(ast, name)

      # Removal must have actually dropped both canonical clauses before we
      # requalify; otherwise we'd rewrite a surviving defp head.
      if defps_named(removed, name) != [] do
        source
      else
        transformed = qualify_calls(removed, name)

        if transformed != ast and not has_reference?(transformed, name) do
          Sourceror.to_string(transformed) <> "\n"
        else
          source
        end
      end
    else
      _ -> source
    end
  end

  defp parse(source) do
    {:ok, Sourceror.parse_string!(source)}
  rescue
    _ -> :error
  end

  defp extract_conflicting_func(%{message: msg}) when is_binary(msg) do
    case Regex.run(~r{Kernel\.(max|min)/2}, msg) do
      [_, name] -> String.to_existing_atom(name)
      _ -> nil
    end
  end

  defp extract_conflicting_func(_), do: nil

  # All `defp name/2` clauses (arity 2 only). If a sibling of a different arity
  # shares the name we deliberately return a list that won't form a canonical
  # pair, so the fix bails.
  defp defps_named(ast, name) do
    {_, acc} =
      Macro.prewalk(ast, [], fn
        {:defp, _, _} = node, acc ->
          if defp_arity2?(node, name), do: {node, [node | acc]}, else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(acc)
  end

  defp defp_arity2?({:defp, _, [{:when, _, [{name, _, args} | _]} | _]}, name)
       when is_list(args),
       do: length(args) == 2

  defp defp_arity2?({:defp, _, [{name, _, args} | _]}, name) when is_list(args),
    do: length(args) == 2

  defp defp_arity2?(_, _), do: false

  # The two clauses must be exactly the canonical reimplementation, in either
  # clause order.
  defp canonical_pair?(name, [d1, d2]) do
    cfg = @configs[name]

    with c1 when c1 != :error <- clause_parts(d1),
         c2 when c2 != :error <- clause_parts(d2) do
      (first_clause?(c1, cfg) and second_clause?(c2, cfg)) or
        (first_clause?(c2, cfg) and second_clause?(c1, cfg))
    else
      _ -> false
    end
  end

  defp canonical_pair?(_, _), do: false

  # Pull {param1, param2, guard_op, guard_left, guard_right, body_var} from a
  # guarded one-line defp clause. Returns :error on any other shape.
  defp clause_parts({:defp, _, [{:when, _, [{_n, _, [p1, p2]}, guard]}, [{_do, body}]]}) do
    with a when is_atom(a) and a != nil <- var_name(p1),
         b when is_atom(b) and b != nil <- var_name(p2),
         {op, gl, gr} <- guard_parts(guard),
         bv when is_atom(bv) and bv != nil <- var_name(body) do
      {a, b, op, gl, gr, bv}
    else
      _ -> :error
    end
  end

  defp clause_parts(_), do: :error

  defp guard_parts({op, _, [l, r]}) when op in [:>=, :>, :<=, :<] do
    with ln when is_atom(ln) and ln != nil <- var_name(l),
         rn when is_atom(rn) and rn != nil <- var_name(r) do
      {op, ln, rn}
    else
      _ -> :error
    end
  end

  defp guard_parts(_), do: :error

  # The tie-inclusive clause: condition is "p1 eq p2", body returns p1.
  defp first_clause?({a, b, op, gl, gr, body}, cfg) do
    body == a and
      ((op == cfg.eq and gl == a and gr == b) or
         (op == cfg.eq_flip and gl == b and gr == a))
  end

  # The strict clause: condition is "p2 strict p1", body returns p2.
  defp second_clause?({a, b, op, gl, gr, body}, cfg) do
    body == b and
      ((op == cfg.st and gl == b and gr == a) or
         (op == cfg.st_flip and gl == a and gr == b))
  end

  defp var_name({n, _, ctx}) when is_atom(n) and is_atom(ctx), do: n
  defp var_name(_), do: nil

  defp remove_defp_arity2(ast, name) do
    Macro.prewalk(ast, fn
      {:__block__, meta, stmts} when is_list(stmts) ->
        {:__block__, meta, Enum.reject(stmts, &defp_arity2?(&1, name))}

      node ->
        node
    end)
  end

  defp qualify_calls(ast, name) do
    Macro.prewalk(ast, fn
      {^name, meta, [_, _] = args} ->
        {{:., [], [{:__aliases__, [], [:Kernel]}, name]}, meta, args}

      node ->
        node
    end)
  end

  # True if any unqualified reference to `name` survives: a call of any arity,
  # or a `&name/n` capture. Used to bail rather than strand a dangling reference
  # to the function we removed.
  defp has_reference?(ast, name) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {^name, _, args} = node, _acc when is_list(args) ->
          {node, true}

        {:&, _, [{:/, _, [fun, _arity]}]} = node, acc ->
          if var_name(fun) == name, do: {node, true}, else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
