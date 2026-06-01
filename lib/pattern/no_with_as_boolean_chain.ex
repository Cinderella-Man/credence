defmodule Credence.Pattern.NoWithAsBooleanChain do
  @moduledoc """
  Detects `with` blocks used as boolean accumulators — where every clause
  is `true <- boolean_expr`, the `do` body returns `true`, and the `else`
  body is a catch-all returning `false`.

  This pattern is just a verbose `and`-chain in disguise.

  ## Bad

      with true <- valid_length?(password),
           true <- has_lowercase?(password),
           true <- has_digit?(password) do
        true
      else
        _ -> false
      end

  ## Good

      valid_length?(password) and
        has_lowercase?(password) and
        has_digit?(password)

  ## Auto-fix

  Replaces the `with` block with an `and`-chain of the right-hand
  expressions from each clause.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:with, meta, args} = node, acc when is_list(args) ->
          if boolean_with_chain?(args) do
            {node, [build_issue(meta) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:with, _meta, args} = node ->
        if boolean_with_chain?(args) do
          rewrite_to_and_chain(node)
        else
          node
        end

      node ->
        node
    end)
  end

  # Returns true when a `with` block has the boolean accumulator pattern:
  #   - All clauses: true <- expr
  #   - do body: true
  #   - else: _ -> false
  defp boolean_with_chain?(args) do
    {clauses, kw} = split_with_args(args)

    with true <- all_true_clauses?(clauses),
         {:ok, do_body, else_clauses} <- extract_do_else(kw) do
      literal_true?(do_body) and catch_all_false?(else_clauses)
    else
      _ -> false
    end
  end

  # Splits the with args into {<- clauses, keyword list}.
  defp split_with_args(args) do
    {clauses, [kw]} = Enum.split(args, -1)
    {clauses, kw}
  end

  # Checks that all clauses are `true <- expr`.
  defp all_true_clauses?(clauses) do
    Enum.all?(clauses, fn
      {:<-, _, [left, _right]} -> literal_true?(left)
      _ -> false
    end)
  end

  # Extracts :do and :else bodies from the keyword list.
  # Handles both standard Elixir and Sourceror-style tuple keys.
  defp extract_do_else(kw) when is_list(kw) do
    do_body = find_keyword_value(kw, :do)
    else_body = find_keyword_value(kw, :else)

    case {do_body, else_body} do
      {nil, _} -> :error
      {_, nil} -> :error
      {do_b, else_b} -> {:ok, do_b, else_b}
    end
  end

  defp find_keyword_value(kw, key) do
    Enum.find_value(kw, fn
      {{:__block__, _, [^key]}, value} -> value
      {^key, value} -> value
      _ -> nil
    end)
  end

  # Checks if an AST node is the literal `true`.
  defp literal_true?(true), do: true
  defp literal_true?({:__block__, _, [true]}), do: true
  defp literal_true?(_), do: false

  # Checks if the else clauses are a catch-all returning `false`.
  defp catch_all_false?([{:->, _, [[pattern], body]}]) do
    wildcard?(pattern) and literal_false?(body)
  end

  defp catch_all_false?(_), do: false

  # Checks if a pattern is a wildcard (`_`).
  defp wildcard?({:_, _, _}), do: true
  defp wildcard?(_), do: false

  # Checks if an AST node is the literal `false`.
  defp literal_false?(false), do: true
  defp literal_false?({:__block__, _, [false]}), do: true
  defp literal_false?(_), do: false

  # Rewrites the `with` block to an `and`-chain.
  defp rewrite_to_and_chain({:with, meta, args}) do
    {clauses, _kw} = split_with_args(args)

    expressions =
      Enum.map(clauses, fn {:<-, _, [_left, right]} -> right end)

    build_and_chain(expressions, meta)
  end

  # Builds a left-associated `and` chain from a list of expressions.
  defp build_and_chain([expr], _meta), do: expr

  defp build_and_chain([first | rest], meta) do
    Enum.reduce(rest, first, fn expr, acc ->
      {:and, meta, [acc, expr]}
    end)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_with_as_boolean_chain,
      message:
        "`with` used as a boolean accumulator is a verbose `and`-chain. " <>
          "Use `and` to chain boolean predicates instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
