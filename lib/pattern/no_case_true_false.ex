defmodule Credence.Pattern.NoCaseTrueFalse do
  @moduledoc """
  Detects `case expr do true -> …; false -> … end` that should be `if/else`.

  LLMs frequently transliterate Python's `if/else` through a `case` on a
  boolean expression with explicit `true`/`false` (or `_`) clauses. Idiomatic
  Elixir uses `if/else` when the condition is already a boolean.

  Only flags cases where the subject is a boolean expression (comparison,
  function call, operator) — not a plain variable, which may be a legitimate
  pattern match on a tristate value.

  Also catches the piped variant: `expr |> case do true -> …; false -> … end`.

  ## Detected patterns

      case expr do true -> A; false -> B end
      case expr do false -> B; true -> A end
      case expr do true -> A; _ -> B end
      case expr do false -> B; _ -> A end
      expr |> case do true -> A; false -> B end

  ## Bad

      case rem(n, 2) == 0 do
        true -> :even
        false -> :odd
      end

  ## Good

      if rem(n, 2) == 0 do
        :even
      else
        :odd
      end

  ## Auto-fix

  Rewrites the `case` to `if/else`, placing the `true` body (or the wildcard
  counterpart) in the `do` block and the `false` body in `else`.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # case expr do true -> …; false -> … end
        {:case, meta, [subject, kw]} = node, acc when is_list(kw) ->
          case extract_do_clauses(kw) do
            [clause_a, clause_b] ->
              if not plain_variable?(subject) and
                   boolean_clause_pair?(clause_pattern(clause_a), clause_pattern(clause_b)) do
                {node, [build_issue(meta) | acc]}
              else
                {node, acc}
              end

            _ ->
              {node, acc}
          end

        # expr |> case do true -> …; false -> … end
        # The case node has only one arg (the keyword block) because the
        # subject is supplied by the pipe on the left.
        {:case, meta, [kw]} = node, acc when is_list(kw) ->
          case extract_do_clauses(kw) do
            [clause_a, clause_b] ->
              if boolean_clause_pair?(clause_pattern(clause_a), clause_pattern(clause_b)) do
                {node, [build_issue(meta) | acc]}
              else
                {node, acc}
              end

            _ ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  # Uses Sourceror for parsing; rewrites matching case nodes to if/else
  # via Macro.postwalk, then emits source with Sourceror.to_string().

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, &maybe_rewrite_case/1)
  end

  # Extract the pattern from a case clause: {:->, _, [[pattern], body]}
  defp clause_pattern({:->, _, [[pattern], _body]}), do: pattern
  defp clause_pattern(_), do: :no_match

  # A plain variable like `some_flag` — legitimate pattern match, not flagged.
  defp plain_variable?({name, _meta, context})
       when is_atom(name) and is_atom(context),
       do: true

  defp plain_variable?(_), do: false

  # Recognises the boolean pairs we flag: true/false, true/_, false/_
  # and their flipped orderings.
  defp boolean_clause_pair?(a, b) do
    case {normalize_pattern(a), normalize_pattern(b)} do
      {true, false} -> true
      {false, true} -> true
      {true, :wildcard} -> true
      {:wildcard, true} -> true
      {false, :wildcard} -> true
      {:wildcard, false} -> true
      _ -> false
    end
  end

  defp normalize_pattern(true), do: true
  defp normalize_pattern(false), do: false
  defp normalize_pattern({:__block__, _, [true]}), do: true
  defp normalize_pattern({:__block__, _, [false]}), do: false
  defp normalize_pattern({:_, _, _}), do: :wildcard
  defp normalize_pattern(_), do: :other

  # Extracts the clause list from a case node's keyword block.
  defp extract_do_clauses([{{:__block__, _, [:do]}, clauses}]) when is_list(clauses),
    do: clauses

  defp extract_do_clauses(_), do: nil

  # Postwalk callback: rewrite a matching case node to if/else.
  # Handles both `case expr do … end` and `expr |> case do … end`.

  # case expr do true -> A; false -> B end
  defp maybe_rewrite_case({:case, meta, [subject, kw]} = node) when is_list(kw) do
    case extract_do_clauses(kw) do
      [clause_a, clause_b] ->
        if plain_variable?(subject) do
          node
        else
          case rewrite_clauses(clause_a, clause_b) do
            {:ok, do_body, else_body} ->
              {:if, meta, [subject, [do: do_body, else: else_body]]}

            :skip ->
              node
          end
        end

      _ ->
        node
    end
  end

  # expr |> case do true -> A; false -> B end
  # The pipe node wraps the case; rewrite the entire pipe to if/else.
  defp maybe_rewrite_case({:|>, _pipe_meta, [expr, {:case, case_meta, [kw]}]} = node)
       when is_list(kw) do
    case extract_do_clauses(kw) do
      [clause_a, clause_b] ->
        if plain_variable?(expr) do
          node
        else
          case rewrite_clauses(clause_a, clause_b) do
            {:ok, do_body, else_body} ->
              {:if, case_meta, [expr, [do: do_body, else: else_body]]}

            :skip ->
              node
          end
        end

      _ ->
        node
    end
  end

  defp maybe_rewrite_case(node), do: node

  # Determines if two clauses form a fixable boolean pair and extracts
  # the correct body placement for if (do = true branch, else = false branch).
  #
  # Returns {:ok, do_body, else_body} or :skip.
  defp rewrite_clauses(clause_a, clause_b) do
    with {pat_a, body_a} <- extract_clause(clause_a),
         {pat_b, body_b} <- extract_clause(clause_b) do
      ua = unwrap_pattern(pat_a)
      ub = unwrap_pattern(pat_b)

      cond do
        # true -> A; false -> B
        ua == true and ub == false -> {:ok, body_a, body_b}
        # false -> B; true -> A
        ua == false and ub == true -> {:ok, body_b, body_a}
        # true -> A; _ -> B
        ua == true and ub == :wildcard -> {:ok, body_a, body_b}
        # false -> B; _ -> A  (wildcard covers the true case)
        ua == false and ub == :wildcard -> {:ok, body_b, body_a}
        # Wildcard-first variants (unreachable second clause) — don't fix
        true -> :skip
      end
    else
      _ -> :skip
    end
  end

  defp extract_clause({:->, _, [[pattern], body]}), do: {pattern, body}
  defp extract_clause(_), do: :error

  # Normalise a clause pattern, handling Sourceror's __block__ wrapping.
  defp unwrap_pattern({:__block__, _, [true]}), do: true
  defp unwrap_pattern({:__block__, _, [false]}), do: false
  defp unwrap_pattern(true), do: true
  defp unwrap_pattern(false), do: false
  defp unwrap_pattern({:_, _, _}), do: :wildcard
  defp unwrap_pattern(_), do: :other

  defp build_issue(meta) do
    %Issue{
      rule: :no_case_true_false,
      message:
        "`case` on a boolean expression with `true`/`false` clauses " <>
          "should be written as `if`/`else`.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
