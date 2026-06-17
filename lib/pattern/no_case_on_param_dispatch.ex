defmodule Credence.Pattern.NoCaseOnParamDispatch do
  @moduledoc """
  Detects a single-parameter function clause whose entire body is a `case`
  that dispatches on that parameter, and rewrites it into multi-clause
  function heads — the idiomatic Elixir way to express this.

  ## Bad

      def pick_coins(coins) do
        case coins do
          [] -> 0
          [first] -> first
          [first, second] -> max(first, second)
          _ -> do_pick_coins(coins, 0, 0)
        end
      end

  ## Good

      def pick_coins([]), do: 0
      def pick_coins([first]), do: first
      def pick_coins([first, second]), do: max(first, second)
      def pick_coins(_ = coins), do: do_pick_coins(coins, 0, 0)

  ## Scope — what it flags

  This rule is deliberately narrowed to a **single-parameter** core where the
  rewrite is provably behaviour-preserving for every input. It fires only when:

  - The clause is a plain `def`/`defp` head (no `when` guard on the head) with
    **exactly one parameter that is a bare variable** `v`.
  - The clause body is **only** a `do:` body (no `rescue`/`catch`/`after`) and
    is a single `case v do … end` whose subject is exactly that parameter.
  - The `case` has at least 2 clauses, **none using a `^` pin** in its pattern.
  - At least one clause is an **unguarded catch-all** (a bare variable or `_`),
    so the `case` is total over the parameter.

  ## Why these limits (safety)

  Each limit closes a way the rewrite could change the answer:

    * **Single bare-variable parameter / subject is that parameter.** A bare
      variable is side-effect-free, so there is no double-evaluation when its
      pattern matching moves into the function head. Multi-parameter / tuple
      dispatch (`case {x, y}`) is *not* flagged — reconstructing reordered or
      partial parameter lists is a separate, riskier transformation.
    * **Totality (an unguarded catch-all).** A non-total `case` raises
      `CaseClauseError`, but the equivalent function heads raise
      `FunctionClauseError` — a different exception. We only fire when both
      constructs are total over the parameter, so neither ever raises.
    * **No `^` pin.** `case v do ^v -> … end` matches against the in-scope
      subject; as a function head `def f(^v)` the pinned variable is unbound.
    * **No `rescue`/`catch`/`after`, body is exactly the `case`.** Any extra
      statement or clause would be silently dropped by the rewrite.

  Guards on individual `case` clauses are preserved verbatim as head guards —
  guard semantics (including error-swallowing) are identical in a `case` clause
  and a function head, so this is safe. Sibling clauses of the same function
  need no special handling: the flagged clause's bare-variable head is itself a
  function-level catch-all, so later siblings are already unreachable and
  earlier siblings shadow identically before and after the rewrite.

  ## Reconstructing the head

  Each `case` clause `pattern -> body` becomes `def name(head) do body end`,
  where `head` keeps the parameter bound when the body or a clause guard still
  refers to it: if `pattern` already binds the parameter name it is used as-is;
  otherwise, when the body/guard mention the parameter, the head becomes
  `pattern = v` so the original name stays in scope.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case convertible(node) do
          {:ok, info} -> {node, [build_issue(info) | acc]}
          :no -> {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn node, acc ->
        case convertible(node) do
          {:ok, info} -> {node, [build_patch(node, info) | acc]}
          :no -> {node, acc}
        end
      end)

    Enum.reverse(patches)
  end

  # ── detection ─────────────────────────────────────────────────────

  # A plain `def`/`defp` head (no function-head `when` guard) with exactly
  # one bare-variable parameter, whose only body is `case <that var> do … end`.
  defp convertible({kind, meta, [{name, _, params}, body_kw]})
       when kind in [:def, :defp] and is_atom(name) and name != :when and is_list(params) do
    with [param] <- params,
         {:var, var} <- bare_var(param),
         {:ok, body} <- do_only_body(body_kw),
         {:ok, subject, clauses} <- unwrap_case(body),
         {:var, ^var} <- bare_var(subject),
         true <- is_list(clauses) and length(clauses) >= 2,
         parsed when is_list(parsed) <- parse_clauses(clauses),
         true <- Enum.any?(parsed, &catch_all?/1) do
      {:ok, %{kind: kind, meta: meta, name: name, var: var, clauses: parsed}}
    else
      _ -> :no
    end
  end

  defp convertible(_), do: :no

  # The body keyword list must be EXACTLY a `do:` body — no rescue/catch/after,
  # which the rewrite would silently drop.
  defp do_only_body([{{:__block__, _, [:do]}, body}]), do: {:ok, body}
  defp do_only_body([{:do, body}]), do: {:ok, body}
  defp do_only_body(_), do: :error

  defp unwrap_case({:__block__, _, [inner]}), do: unwrap_case(inner)

  defp unwrap_case({:case, _, [subject, case_kw]}) do
    case do_only_body(case_kw) do
      {:ok, clauses} -> {:ok, subject, clauses}
      :error -> :error
    end
  end

  defp unwrap_case(_), do: :error

  # Returns {:var, name} for a bare variable node, else :error.
  defp bare_var({:__block__, _, [inner]}), do: bare_var(inner)
  defp bare_var({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: {:var, name}
  defp bare_var(_), do: :error

  # Parse each case clause into {pattern, guard | nil, body}, or :error if any
  # clause has an unexpected shape or its pattern contains a `^` pin.
  defp parse_clauses(clauses) do
    Enum.reduce_while(clauses, [], fn clause, acc ->
      case parse_clause(clause) do
        {:ok, parsed} -> {:cont, [parsed | acc]}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      :error -> :error
      reversed -> Enum.reverse(reversed)
    end
  end

  defp parse_clause({:->, meta, [[{:when, _, [pattern, guard]}], body]}) do
    if has_pin?(pattern), do: :error, else: {:ok, {pattern, guard, body, meta}}
  end

  defp parse_clause({:->, meta, [[pattern], body]}) do
    if has_pin?(pattern), do: :error, else: {:ok, {pattern, nil, body, meta}}
  end

  defp parse_clause(_), do: :error

  defp catch_all?({pattern, nil, _body, _meta}), do: match?({:var, _}, bare_var(pattern))
  defp catch_all?(_), do: false

  defp has_pin?(ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {:^, _, _} = node, _ -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  # ── rewrite ───────────────────────────────────────────────────────

  defp build_patch(node, %{kind: kind, name: name, var: var, clauses: clauses}) do
    range = Sourceror.get_range(node)

    change =
      Enum.map_join(clauses, "\n", &clause_to_head(&1, kind, name, var, range))

    %{range: range, change: change}
  end

  defp clause_to_head({pattern, guard, body, clause_meta}, kind, name, var, range) do
    head_pattern = build_head_pattern(pattern, guard, body, var)
    call = {name, [], [head_pattern]}
    head = if guard, do: {:when, [], [call, guard]}, else: call
    # The def needs a `:line` for Sourceror to anchor a leading comment to it.
    def_ast = {kind, [line: 1], [head, [{{:__block__, [], [:do]}, body}]]}

    # The case clause's own comments (e.g. one documenting why the clause exists)
    # sat on the `:->` node, which is discarded — carry them onto the generated
    # `def` so they are not lost; `carry_comments` re-lines them to render before
    # the head.
    leading = Keyword.get(clause_meta, :leading_comments, [])
    trailing = Keyword.get(clause_meta, :trailing_comments, [])

    def_ast
    |> RuleHelpers.carry_comments(leading, trailing)
    |> RuleHelpers.render_replacement(range)
  end

  # Keep the parameter bound when the body or guard still refer to it.
  defp build_head_pattern(pattern, guard, body, var) do
    cond do
      binds_var?(pattern, var) -> pattern
      mentions_var?(body, var) or mentions_var?(guard, var) -> {:=, [], [pattern, {var, [], nil}]}
      true -> pattern
    end
  end

  # Does `var` appear as a bound variable anywhere in a pattern? (Patterns have
  # no `^` pins here — they are rejected upstream — so every matching var node
  # is a binding occurrence.)
  defp binds_var?(pattern, var), do: mentions_var?(pattern, var)

  defp mentions_var?(nil, _var), do: false

  defp mentions_var?(ast, var) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {^var, _, ctx} = node, _ when is_atom(ctx) -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  # ── issue ─────────────────────────────────────────────────────────

  defp build_issue(%{meta: meta}) do
    %Issue{
      rule: :no_case_on_param_dispatch,
      message:
        "A `case` dispatching on a function parameter should use multi-clause " <>
          "function heads instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
