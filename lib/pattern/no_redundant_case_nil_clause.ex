defmodule Credence.Pattern.NoRedundantCaseNilClause do
  @moduledoc """
  Detects `case` expressions where a `nil` clause and a trailing wildcard
  clause have identical bodies, and the intermediate guarded clause can be
  extended with `not is_nil/1` to absorb the `nil` case.

  In Erlang term ordering, atoms (including `nil`) sort above numbers, so
  `nil >= 0` is `true`. LLMs frequently write an explicit `nil ->` guard
  before a `var when var >= threshold ->` clause to prevent nil from
  matching, then add a catch-all wildcard that duplicates the nil body.
  An expert would add `not is_nil(var)` to the guard and drop the
  redundant nil clause.

  ## Detected patterns

      case expr do
        nil -> body_a
        var when guard -> body_b
        _ -> body_a          # identical to nil body
      end

  ## Good

      case expr do
        var when not is_nil(var) and guard -> body_b
        _ -> body_a
      end

  ## Auto-fix

  Removes the `nil` clause and prepends `not is_nil(var) and` to the
  existing guard of the middle clause.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:case, meta, [_subject, kw]} = node, acc when is_list(kw) ->
          check_case(kw, node, acc, meta)

        {:case, meta, [kw]} = node, acc when is_list(kw) ->
          check_case(kw, node, acc, meta)

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    transformed = maybe_fix(ast)
    patches_between(ast, transformed)
  end

  # Emit one patch per *matching* `case` node, rendering the whole node.
  #
  # Removing the `nil` clause shortens the `do` clause list (3 → 2). The
  # generic AST-diff helper would land its patch on the clause *list* and
  # render a bare list of `->` clauses, which Sourceror wraps in stray
  # parens (`case x do ( ... ) end`). Patching at the `case`-node level
  # instead renders a clean `case ... do ... end`. `maybe_fix` already
  # fixed any nested cases (it is a `postwalk`), so the rendered node
  # carries those fixes — we short-circuit at the matching case and do
  # not recurse into it, keeping patches non-overlapping.

  defp patches_between(same, same), do: []

  defp patches_between({:case, _, args_o} = orig, {:case, _, args_m} = modified) do
    if case_matches?(orig) do
      case Sourceror.get_range(orig) do
        %Sourceror.Range{} = range ->
          [%{range: range, change: Credence.RuleHelpers.render_replacement(modified, range)}]

        _ ->
          []
      end
    else
      zip_recurse(args_o, args_m)
    end
  end

  defp patches_between({form, _, args_o}, {form, _, args_m})
       when is_list(args_o) and is_list(args_m) and length(args_o) == length(args_m) do
    zip_recurse(args_o, args_m)
  end

  defp patches_between([_ | _] = orig, [_ | _] = modified)
       when length(orig) == length(modified) do
    zip_recurse(orig, modified)
  end

  defp patches_between({a_o, b_o}, {a_m, b_m}) do
    patches_between(a_o, a_m) ++ patches_between(b_o, b_m)
  end

  defp patches_between(_, _), do: []

  defp zip_recurse(orig, modified) do
    orig
    |> Enum.zip(modified)
    |> Enum.flat_map(fn {o, m} -> patches_between(o, m) end)
  end

  defp case_matches?({:case, _, [_subject, kw]}) when is_list(kw), do: kw_matches?(kw)
  defp case_matches?({:case, _, [kw]}) when is_list(kw), do: kw_matches?(kw)
  defp case_matches?(_), do: false

  defp kw_matches?(kw) do
    case extract_do_clauses(kw) do
      [first, middle, last] -> redundant_nil_clause?(first, middle, last)
      _ -> false
    end
  end

  # ── detection ──────────────────────────────────────────────────────

  defp check_case(kw, node, acc, meta) do
    case extract_do_clauses(kw) do
      [first, middle, last] ->
        if redundant_nil_clause?(first, middle, last) do
          {node, [build_issue(meta) | acc]}
        else
          {node, acc}
        end

      _ ->
        {node, acc}
    end
  end

  defp redundant_nil_clause?(first, middle, last) do
    nil_clause?(first) and wildcard_clause?(last) and guarded_clause?(middle) and
      bodies_equivalent?(first, last)
  end

  defp extract_do_clauses([{{:__block__, _, [:do]}, clauses}]) when is_list(clauses),
    do: clauses

  defp extract_do_clauses(_), do: nil

  # ── pattern predicates ─────────────────────────────────────────────

  defp nil_clause?({:->, _, [[pattern], _body]}), do: nil_pattern?(pattern)
  defp nil_clause?(_), do: false

  defp nil_pattern?(nil), do: true
  defp nil_pattern?({:__block__, _, [nil]}), do: true
  defp nil_pattern?(_), do: false

  defp wildcard_clause?({:->, _, [[pattern], _body]}), do: wildcard_pattern?(pattern)
  defp wildcard_clause?(_), do: false

  defp wildcard_pattern?({:_, _, _}), do: true

  defp wildcard_pattern?({name, _, ctx}) when is_atom(name) and is_atom(ctx),
    do: name |> to_string() |> String.starts_with?("_")

  defp wildcard_pattern?(_), do: false

  # Only a *bare variable* middle pattern is a safe target. The fix reuses
  # the pattern as an expression inside `not is_nil(...)`; for a bare
  # variable that is exactly `is_nil(var)`, the documented LLM anti-pattern
  # (`var when var >= threshold`). Any other pattern is rejected:
  #   - a tuple/map/list/literal makes `not is_nil(...)` always-true dead
  #     code an expert would never write, and
  #   - a match pattern (`r = {:ok, v}`) renders `is_nil(r = {:ok, v})`,
  #     which does not compile (`=` is not allowed in guards).
  defp guarded_clause?({:->, _, [[{:when, _, [var, _guard]}], _body]}), do: bare_var?(var)
  defp guarded_clause?(_), do: false

  defp bare_var?({name, _, ctx}) when is_atom(name) and is_atom(ctx) do
    not (name |> to_string() |> String.starts_with?("_"))
  end

  defp bare_var?(_), do: false

  defp bodies_equivalent?({:->, _, [[_], body_a]}, {:->, _, [[_], body_b]}) do
    Macro.to_string(body_a) == Macro.to_string(body_b)
  end

  defp bodies_equivalent?(_, _), do: false

  # ── issue ──────────────────────────────────────────────────────────

  defp build_issue(meta) do
    %Issue{
      rule: :no_redundant_case_nil_clause,
      message:
        "The `nil` clause and the wildcard clause have identical bodies. " <>
          "Add `not is_nil(var)` to the guard and remove the `nil` clause.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  # ── auto-fix ───────────────────────────────────────────────────────

  defp maybe_fix(ast) do
    Macro.postwalk(ast, fn
      # case expr do ... end
      {:case, meta, [subject, kw]} = node when is_list(kw) ->
        case extract_do_clauses(kw) do
          [first, middle, last] ->
            if redundant_nil_clause?(first, middle, last) do
              new_middle = add_nil_guard(middle)
              {:case, meta, [subject, replace_clauses(kw, [new_middle, last])]}
            else
              node
            end

          _ ->
            node
        end

      # expr |> case do ... end
      {:case, meta, [kw]} = node when is_list(kw) ->
        case extract_do_clauses(kw) do
          [first, middle, last] ->
            if redundant_nil_clause?(first, middle, last) do
              new_middle = add_nil_guard(middle)
              {:case, meta, [replace_clauses(kw, [new_middle, last])]}
            else
              node
            end

          _ ->
            node
        end

      node ->
        node
    end)
  end

  defp replace_clauses([{{:__block__, block_meta, [:do]}, _old_clauses}], new_clauses) do
    [{{:__block__, block_meta, [:do]}, new_clauses}]
  end

  defp add_nil_guard({:->, clause_meta, [[{:when, when_meta, [var, guard]}], body]}) do
    nil_guard = {:not, [], [{:is_nil, [], [var]}]}
    new_guard = {:and, [], [nil_guard, guard]}
    {:->, clause_meta, [[{:when, when_meta, [var, new_guard]}], body]}
  end
end
