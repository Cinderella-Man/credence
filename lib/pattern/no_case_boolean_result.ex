defmodule Credence.Pattern.NoCaseBooleanResult do
  @moduledoc """
  Detects a two-clause `case` that converts a value to a boolean by matching
  a specific pattern against a trailing wildcard, and rewrites it to `match?/2`.

  Note: this is the *inverse* of `no_case_true_false`, which catches
  `case bool_expr do true -> …; false -> … end`.  This rule catches
  `case expr do :ok -> true; _ -> false end`.

  ## Detected patterns (and their fixes)

      case expr do :ok -> true; _ -> false end   →   match?(:ok, expr)
      case expr do :ok -> false; _ -> true end   →   not match?(:ok, expr)

      expr |> case do
        :ok -> true
        _ -> false
      end                                         →   match?(:ok, expr)

  The fired-on shape is exactly: **two clauses, a specific (non-boolean,
  non-variable) pattern returning a boolean, then a wildcard (`_`) returning
  the opposite boolean.** For such a `case`, `match?/2` gives the identical
  answer on every input: the specific clause matches the same values, and the
  wildcard covers all the rest.

  ## Deliberately *not* matched (no safe same-answer fix)

    * **Two specific patterns** (`:ok -> true; :no -> false`) — the `case`
      raises `CaseClauseError` on any other value, while a comparison returns
      `false`. Different answer, so not flagged.
    * **Wildcard *first*** (`_ -> false; :ok -> true`) — the wildcard matches
      everything, so the second clause is dead and the `case` is a constant.
      `match?/2` is not constant, so not flagged.
    * **A bare variable pattern** (`x -> true; _ -> false`) — the variable
      matches everything, so the `case` is again constant. Not flagged.
  """

  use Credence.Pattern.Rule
  # CONSERVATIVE. Ash.Expr and Ecto.Query are closed — neither admits `case` in
  # an expression (Ecto raises a CompileError; Ash has if/cond only and turns a
  # `case` node into an unresolvable Call), so the matcher cannot fire in
  # compiling code there. Nx.Defn is NOT closed: defn does admit `case` on
  # trace-time values (e.g. `case Nx.type(t) do {:f, _} -> false; _ -> true
  # end`), and defn's `not` is element-wise `Nx.logical_not`, so the `pattern ->
  # false; _ -> true` variant returns a u8 tensor where the `case` returned a
  # plain boolean — a silent divergence. What I could not settle: whether defn
  # accepts `match?/2` at all (if it compile-errors, the compile gate reverts
  # the fix and no family needs listing — the same reason
  # `prefer_negate_if_true_false` omits Ecto). Declared rather than allowlisted
  # because the deciding check needs the DSL itself as a dependency, which this
  # repo does not carry; declaring costs a missed fix inside the block,
  # allowlisting would cost a wrong rewrite.
  @impl true
  def unsafe_in_dsl, do: [:nx_defn]
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # case expr do ... end
        {:case, meta, [_subject, kw]} = node, acc when is_list(kw) ->
          check_case_clauses(kw, node, acc, meta)

        # expr |> case do ... end
        {:case, meta, [kw]} = node, acc when is_list(kw) ->
          check_case_clauses(kw, node, acc, meta)

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, &maybe_rewrite/1)
  end

  defp check_case_clauses(kw, node, acc, meta) do
    case extract_do_clauses(kw) do
      [clause_a, clause_b] ->
        if classify(clause_a, clause_b) != :skip do
          {node, [build_issue(meta) | acc]}
        else
          {node, acc}
        end

      _ ->
        {node, acc}
    end
  end

  defp unwrap_boolean(true), do: true
  defp unwrap_boolean(false), do: false
  defp unwrap_boolean({:__block__, _, [true]}), do: true
  defp unwrap_boolean({:__block__, _, [false]}), do: false
  defp unwrap_boolean(_), do: :other

  defp extract_do_clauses([{{:__block__, _, [:do]}, clauses}]) when is_list(clauses),
    do: clauses

  defp extract_do_clauses(_), do: nil

  # --- auto-fix: rewrite the safe wildcard-last case to match?/2 ---

  # case expr do ... end
  defp maybe_rewrite({:case, _meta, [subject, kw]} = node) when is_list(kw) do
    rewrite_case(kw, subject, node)
  end

  # expr |> case do ... end
  defp maybe_rewrite({:|>, _pipe_meta, [subject, {:case, _case_meta, [kw]}]} = node)
       when is_list(kw) do
    rewrite_case(kw, subject, node)
  end

  defp maybe_rewrite(node), do: node

  defp rewrite_case(kw, subject, node) do
    case extract_do_clauses(kw) do
      [clause_a, clause_b] ->
        case classify(clause_a, clause_b) do
          {:match, pattern} -> {:match?, [], [pattern, subject]}
          {:not_match, pattern} -> {:not, [], [{:match?, [], [pattern, subject]}]}
          :skip -> node
        end

      _ ->
        node
    end
  end

  defp extract_clause({:->, _, [[pattern], body]}), do: {pattern, body}
  defp extract_clause(_), do: :error

  # The single source of truth shared by check/2 and fix_patches/2: a two-clause
  # `case` is safe to rewrite ONLY as `pattern -> bool; _ -> opposite_bool`, with
  # the wildcard LAST and `pattern` a specific, non-variable pattern. Returns
  # `{:match, pattern}`, `{:not_match, pattern}`, or `:skip`.
  defp classify(clause_a, clause_b) do
    with {pat_a, body_a} <- extract_clause(clause_a),
         {pat_b, body_b} <- extract_clause(clause_b) do
      specific_first? =
        normalize_pattern(pat_a) == :other and
          normalize_pattern(pat_b) == :wildcard and
          not variable_pattern?(pat_a)

      cond do
        specific_first? and unwrap_boolean(body_a) == true and
            unwrap_boolean(body_b) == false ->
          {:match, strip_block(pat_a)}

        specific_first? and unwrap_boolean(body_a) == false and
            unwrap_boolean(body_b) == true ->
          {:not_match, strip_block(pat_a)}

        true ->
          :skip
      end
    else
      _ -> :skip
    end
  end

  # A bare variable binding like `x` — not a useful match? pattern.
  defp variable_pattern?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp variable_pattern?(_), do: false

  # Strip Sourceror's {:__block__, _, [value]} wrapper for use in match?/2.
  defp strip_block({:__block__, _, [value]}), do: value
  defp strip_block(other), do: other

  defp normalize_pattern(true), do: :boolean
  defp normalize_pattern(false), do: :boolean
  defp normalize_pattern({:__block__, _, [true]}), do: :boolean
  defp normalize_pattern({:__block__, _, [false]}), do: :boolean
  defp normalize_pattern({:_, _, _}), do: :wildcard
  defp normalize_pattern(_), do: :other

  defp build_issue(meta) do
    %Issue{
      rule: :no_case_boolean_result,
      message:
        "`case` that converts non-boolean values to booleans " <>
          "could be replaced with a direct comparison or `match?/2`.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
