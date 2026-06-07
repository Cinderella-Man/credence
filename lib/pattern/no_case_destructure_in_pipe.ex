defmodule Credence.Pattern.NoCaseDestructureInPipe do
  @moduledoc """
  Readability rule: Detects a single-clause `case` used inside a pipeline
  whose clause head is an **irrefutable** variable pattern (a bare variable
  or `_`, with no guard). That shape is exactly equivalent to `then/1` and
  is non-idiomatic.

  LLMs often use `|> case do pattern -> body end` as a workaround when
  `|> (fn ... end).()` is caught by `no_anon_fn_application_in_pipe`.
  Both are non-idiomatic; `then/1` is the idiomatic alternative.

  ## Bad

      result
      |> compute()
      |> case do
        value -> value + 1
      end

  ## Good

      result
      |> compute()
      |> then(fn value -> value + 1 end)

  ## Why only irrefutable patterns

  A refutable pattern (e.g. `{x, acc}`, `{:ok, v}`, a pin, or any clause
  with a guard) is **not** safe to rewrite. When the piped value does not
  match, a single-clause `case` raises `CaseClauseError` while
  `then(fn pattern -> ... end)` raises `FunctionClauseError`. Those are
  different exceptions, so a caller that rescues `CaseClauseError` would
  behave differently after the rewrite. An irrefutable variable pattern
  always matches, so there is no divergent error path and the rewrite is
  answer-preserving for every input.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Match: ... |> case do single_clause -> body end
        # In the pipe AST, the case node has a single arg (the keyword block)
        # because the subject comes from the pipe.
        {:|>, meta, [_left, {:case, _case_meta, [kw]}]} = node, issues
        when is_list(kw) ->
          case safe_single_clause(kw) do
            {:ok, _pattern, _body} ->
              issue = %Issue{
                rule: :no_case_destructure_in_pipe,
                message:
                  "A single-clause `case` in a pipeline should use `then/1` instead: " <>
                    "`|> then(fn pattern -> body end)`.",
                meta: %{line: Keyword.get(meta, :line)}
              }

              {node, [issue | issues]}

            :no_match ->
              {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      # |> case do pattern -> body end  →  |> then(fn pattern -> body end)
      {:|>, pipe_meta, [left, {:case, _case_meta, [kw]}]} = node
      when is_list(kw) ->
        case safe_single_clause(kw) do
          {:ok, pattern, body} ->
            fn_node =
              {:fn, [], [{:->, [], [[pattern], body]}]}

            {:|>, pipe_meta, [left, {:then, [], [fn_node]}]}

          :no_match ->
            node
        end

      node ->
        node
    end)
  end

  # Extract the single, *irrefutable* clause from a case keyword block.
  # Returns {:ok, pattern, body} only when the case has exactly one clause
  # whose head is a bare variable (or `_`) with no guard — the one shape that
  # always matches, so rewriting to `then/1` cannot change the error path.
  # Returns :no_match otherwise.
  defp safe_single_clause([{{:__block__, _, [:do]}, clauses}])
       when is_list(clauses) do
    single_irrefutable_clause(clauses)
  end

  defp safe_single_clause([{:do, clauses}]) when is_list(clauses) do
    single_irrefutable_clause(clauses)
  end

  defp safe_single_clause(_), do: :no_match

  defp single_irrefutable_clause([{:->, _, [[pattern], body]}]) do
    if irrefutable_var?(pattern), do: {:ok, pattern, body}, else: :no_match
  end

  defp single_irrefutable_clause(_), do: :no_match

  # An irrefutable variable pattern: `value`, `_`, `_x`, etc. In the AST a
  # variable is `{name, _meta, context}` with both `name` and `context` atoms.
  # Calls (`foo()` -> context is a list), pins (`^v`), tuples, literals, and
  # guarded heads (`{:when, _, [...]}`) all fail this and are left alone.
  defp irrefutable_var?({name, _meta, context})
       when is_atom(name) and is_atom(context),
       do: true

  defp irrefutable_var?(_), do: false
end
