defmodule Credence.Pattern.NoCaseDestructureInPipe do
  @moduledoc """
  Readability rule: Detects `case` with a single clause used inside a
  pipeline. A single-clause `case` in a pipe is always equivalent to
  `then/1` and is non-idiomatic.

  LLMs often use `|> case do pattern -> body end` as a workaround when
  `|> (fn ... end).()` is caught by `no_anon_fn_application_in_pipe`.
  Both are non-idiomatic; `then/1` is the idiomatic alternative.

  ## Bad

      result
      |> Enum.reduce({0, 0}, fn x, acc -> {x, acc} end)
      |> case do
        {x, acc} -> x + acc
      end

  ## Good

      result
      |> Enum.reduce({0, 0}, fn x, acc -> {x, acc} end)
      |> then(fn {x, acc} -> x + acc end)
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
          case extract_single_clause(kw) do
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
        case extract_single_clause(kw) do
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

  # Extract a single clause from a case keyword block.
  # Returns {:ok, pattern, body} or :no_match.
  defp extract_single_clause([{{:__block__, _, [:do]}, clauses}])
       when is_list(clauses) do
    case clauses do
      [{:->, _, [[pattern], body]}] -> {:ok, pattern, body}
      _ -> :no_match
    end
  end

  defp extract_single_clause([{:do, clauses}]) when is_list(clauses) do
    case clauses do
      [{:->, _, [[pattern], body]}] -> {:ok, pattern, body}
      _ -> :no_match
    end
  end

  defp extract_single_clause(_), do: :no_match

end
