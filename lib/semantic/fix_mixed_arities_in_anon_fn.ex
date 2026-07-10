defmodule Credence.Semantic.FixMixedAritiesInAnonFn do
  @moduledoc """
  Fixes the compile error "cannot mix clauses with different arities in anonymous
  functions" by padding shorter `fn` clauses so every clause shares the same arity.

  LLMs sometimes generate anonymous functions whose `->` clauses have different
  arities — e.g. a two-parameter clause and a one-parameter catch-all:

      fn {name, val}, acc -> [{name, val} | acc] ; _ -> acc end

  Elixir rejects this at compile time.  The fix pads shorter clause(s) up to the
  maximum arity found across the fn.  Where a longer clause has a simple variable
  at the missing position, the same variable name is reused (resolving the
  companion "undefined variable" error); otherwise a `_` wildcard is inserted:

      fn {name, val}, acc -> [{name, val} | acc] ; _, acc -> acc end
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

  # Walk the AST manually so we can stop descent into fn nodes once they are
  # fixed (Macro.prewalk would re-descend into the already-padded children).
  # Returns {new_ast, changed?}.
  defp walk_and_fix(list) when is_list(list) do
    {results, changed?} =
      Enum.reduce(list, {[], false}, fn item, {acc, ch?} ->
        {walked, item_changed?} = walk_and_fix(item)
        {acc ++ [walked], ch? or item_changed?}
      end)

    {results, changed?}
  end

  defp walk_and_fix({:fn, fn_meta, clauses} = node) when is_list(clauses) and length(clauses) > 1 do
    arities = Enum.map(clauses, &clause_arity/1)
    max_arity = Enum.max(arities)

    if Enum.any?(arities, &(&1 < max_arity)) do
      # For each position, prefer a simple variable name from longer clauses.
      padding_by_pos = build_padding_map(clauses, max_arity)
      padded = Enum.map(clauses, &pad_clause(&1, max_arity, padding_by_pos))
      {{:fn, fn_meta, padded}, true}
    else
      {node, false}
    end
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

  # Count the parameters in a fn clause.
  defp clause_arity({:->, _, [params, _]}) when is_list(params), do: length(params)
  defp clause_arity(_), do: 0

  # Build a map of position → padding node.  If any clause has a simple variable
  # at that position, reuse its name; otherwise use `_`.
  defp build_padding_map(clauses, max_arity) do
    for pos <- 0..(max_arity - 1), into: %{} do
      var =
        Enum.find_value(clauses, fn
          {:->, _, [params, _]} when is_list(params) and length(params) > pos ->
            case Enum.at(params, pos) do
              {name, _meta, ctx} when is_atom(name) and ctx in [nil, Elixir] ->
                {name, [line: 0], Elixir}

              _ ->
                nil
            end

          _ ->
            nil
        end)

      {pos, var || {:_, [line: 0], Elixir}}
    end
  end

  # Pad a clause's parameter list to the target arity using the padding map.
  defp pad_clause({:->, meta, [params, body]}, target, padding_map) when is_list(params) do
    current = length(params)

    if current < target do
      new_params = params ++ Enum.map(current..(target - 1), &Map.fetch!(padding_map, &1))
      {:->, meta, [new_params, body]}
    else
      {:->, meta, [params, body]}
    end
  end

  defp pad_clause(clause, _target, _padding_map), do: clause

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
