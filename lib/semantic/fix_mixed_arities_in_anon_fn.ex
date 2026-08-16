defmodule Credence.Semantic.FixMixedAritiesInAnonFn do
  @moduledoc """
  Fixes the compile error "cannot mix clauses with different arities in anonymous
  functions" by padding shorter `fn` clauses so every clause shares the same arity.

  LLMs sometimes generate anonymous functions whose `->` clauses have different
  arities — e.g. a two-parameter clause and a one-parameter catch-all:

      fn {name, val}, acc -> [{name, val} | acc] ; _ -> acc end

  Elixir rejects this at compile time.  The fix pads shorter clause(s) up to the
  maximum arity found across the fn.  Where a longer clause has a simple variable
  at the missing position **and the shorter clause's body uses that name**, the
  same variable name is reused (resolving the companion "undefined variable"
  error); otherwise a `_` wildcard is inserted so the fix never introduces an
  unused-variable warning:

      fn {name, val}, acc -> [{name, val} | acc] ; _, acc -> acc end

  Clause guards are handled: a guarded clause's real parameters live inside its
  `when` node, and padding is inserted before the guard
  (`fn a, b, c -> a; x when x > 0 -> x end` becomes
  `fn a, b, c -> a; x, _, _ when x > 0 -> x end`).

  ## Deliberately skipped (no fix)

  The `should_report?/2` phase hook reports an issue only when the fix would
  rewrite the source.

  - `fn` clauses with a misplaced `when` between parameters
    (`fn {k, v} when k > 0, acc -> ...`): that shape is
    `Credence.Semantic.FixFnGuardPosition`'s domain; padding around it would
    still leave uncompilable code.

  ## Bad

      f = fn x, y -> x + y; _ -> 0 end

  ## Good

      _f = fn
        x, y -> x + y
        _, _ -> 0
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "cannot mix clauses with different arities in anonymous functions"

  @impl true
  def match?(%{severity: sev, message: msg})
      when sev in [:warning, :error] and is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

  @doc """
  Phase hook (`Credence.Semantic.match_rules/2`): report an issue only when
  `fix/2` would actually rewrite the source.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_mixed_arities_in_anon_fn,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {fixed, changed?} = walk_and_fix(ast)
      if changed?, do: Sourceror.to_string(fixed), else: source
    else
      _ -> source
    end
  end

  # Walk the AST manually; multi-clause fn nodes are padded first and their
  # (padded) clauses are then walked like any other children, so nested fns
  # inside clause bodies are fixed too.  Returns {new_ast, changed?}.
  defp walk_and_fix(list) when is_list(list) do
    Enum.map_reduce(list, false, fn item, ch? ->
      {walked, item_changed?} = walk_and_fix(item)
      {walked, ch? or item_changed?}
    end)
  end

  defp walk_and_fix({:fn, fn_meta, clauses}) when is_list(clauses) and length(clauses) > 1 do
    {padded, padded?} = maybe_pad_clauses(clauses)
    {walked, child_changed?} = walk_and_fix(padded)
    {{:fn, fn_meta, walked}, padded? or child_changed?}
  end

  defp walk_and_fix({tag, meta, children}) when is_list(children) do
    {walked_children, changed?} = walk_and_fix(children)
    {{tag, meta, walked_children}, changed?}
  end

  defp walk_and_fix({left, right}) do
    {wl, cl} = walk_and_fix(left)
    {wr, cr} = walk_and_fix(right)
    {{wl, wr}, cl or cr}
  end

  defp walk_and_fix(other), do: {other, false}

  defp maybe_pad_clauses(clauses) do
    if Enum.all?(clauses, &well_formed_clause?/1) do
      arities = Enum.map(clauses, &clause_arity/1)
      max_arity = Enum.max(arities)

      if Enum.any?(arities, &(&1 < max_arity)) do
        # For each position, prefer a simple variable name from longer clauses.
        padding_by_pos = build_padding_map(clauses, max_arity)
        {Enum.map(clauses, &pad_clause(&1, max_arity, padding_by_pos)), true}
      else
        {clauses, false}
      end
    else
      {clauses, false}
    end
  end

  # A clause this rule knows how to pad: either a plain parameter list, or the
  # whole head wrapped in a single `when` node (params + guard).  A `when` node
  # sitting between parameters is a misplaced guard (FixFnGuardPosition's
  # domain) — padding around it would still leave uncompilable code.
  defp well_formed_clause?({:->, _, [params, _body]}) when is_list(params) do
    case params do
      [{:when, _, args}] when is_list(args) and length(args) >= 2 -> true
      _ -> not Enum.any?(params, &match?({:when, _, _}, &1))
    end
  end

  defp well_formed_clause?(_), do: false

  # The clause's real parameters — for a guarded clause they live inside the
  # `when` node, all elements but the last (the guard; chained guards nest in
  # that last element).
  defp clause_params({:->, _, [[{:when, _, when_args}], _body]}) when is_list(when_args) do
    Enum.drop(when_args, -1)
  end

  defp clause_params({:->, _, [params, _body]}) when is_list(params), do: params

  defp clause_arity(clause), do: length(clause_params(clause))

  # Map of position → candidate variable name (or nil).  If any clause has a
  # simple variable at that position, its name is the candidate.
  defp build_padding_map(clauses, max_arity) do
    for pos <- 0..(max_arity - 1), into: %{} do
      name =
        Enum.find_value(clauses, fn clause ->
          case Enum.at(clause_params(clause), pos) do
            {name, _meta, ctx} when is_atom(name) and is_atom(ctx) and name != :_ -> name
            _ -> nil
          end
        end)

      {pos, name}
    end
  end

  # Pad a clause's parameter list to the target arity.  A candidate name is
  # only reused when the clause's body references it (binding it resolves the
  # companion "undefined variable" error); otherwise `_` keeps the fix free of
  # unused-variable warnings.
  defp pad_clause({:->, meta, [head, body]} = clause, target, padding_map) do
    params = clause_params(clause)
    current = length(params)

    if current < target do
      padding =
        Enum.map(current..(target - 1), fn pos ->
          name = Map.fetch!(padding_map, pos)

          if name && var_used?(body, name) do
            {name, [line: 0], nil}
          else
            {:_, [line: 0], nil}
          end
        end)

      new_head =
        case head do
          [{:when, when_meta, when_args}] ->
            {when_params, [guard]} = Enum.split(when_args, -1)
            [{:when, when_meta, when_params ++ padding ++ [guard]}]

          plain when is_list(plain) ->
            plain ++ padding
        end

      {:->, meta, [new_head, body]}
    else
      clause
    end
  end

  defp pad_clause(clause, _target, _padding_map), do: clause

  # True when `name` occurs as a variable anywhere in `body`.
  defp var_used?(body, name) do
    {_, used?} =
      Macro.prewalk(body, false, fn
        {^name, _, ctx} = node, _acc when is_atom(ctx) -> {node, true}
        node, acc -> {node, acc}
      end)

    used?
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
