defmodule Credence.Pattern.NoIfTrueFalse do
  @moduledoc """
  Detects `if condition do true else false end` that should be just `condition`.

  LLMs frequently emit this redundant boolean wrapper when the condition
  already evaluates to a boolean. An `if` whose `do` branch returns `true`
  and whose `else` branch returns `false` (or a wildcard default) is
  semantically identical to the condition itself.

  Also catches the piped variant: `condition |> if(do: true, else: false)`.

  ## Detected patterns

      if condition do true else false end
      if condition, do: true, else: false
      if condition do true; else: false end

  ## Bad

      if match?([_, _, _, _], parts) and Enum.all?(parts, &valid?/1) do
        true
      else
        false
      end

  ## Good

      match?([_, _, _, _], parts) and Enum.all?(parts, &valid?/1)

  ## Auto-fix

  Replaces the entire `if/else` with the condition expression.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:if, meta, [_condition, clauses]} = node, acc when is_list(clauses) ->
          if redundant_boolean_if?(clauses) do
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
    Credence.RuleHelpers.patches_from_postwalk(ast, &maybe_rewrite/1)
  end

  # Checks if an if's clause list is do: true, else: false (or vice versa).
  defp redundant_boolean_if?(clauses) when is_list(clauses) do
    do_body = extract_clause(clauses, :do)
    else_body = extract_clause(clauses, :else)

    # Only match do: true, else: false. The reversed case (do: false, else: true)
    # would require negating the condition, which is complex and error-prone.
    case {normalize_bool(do_body), normalize_bool(else_body)} do
      {true, false} -> true
      _ -> false
    end
  end

  defp redundant_boolean_if?(_), do: false

  # Extracts the body for a given clause key (:do or :else).
  defp extract_clause(clauses, key) do
    Enum.find_value(clauses, fn
      {{:__block__, _, [^key]}, body} -> body
      _ -> nil
    end)
  end

  # Normalizes AST representations of boolean literals.
  defp normalize_bool(true), do: true
  defp normalize_bool(false), do: false
  defp normalize_bool({:__block__, _, [true]}), do: true
  defp normalize_bool({:__block__, _, [false]}), do: false
  defp normalize_bool(_), do: :other

  # Rewrites `if condition do true else false end` to just `condition`.
  defp maybe_rewrite({:if, _meta, [condition, clauses]} = node) when is_list(clauses) do
    if redundant_boolean_if?(clauses) do
      condition
    else
      node
    end
  end

  defp maybe_rewrite(node), do: node

  defp build_issue(meta) do
    %Issue{
      rule: :no_if_true_false,
      message:
        "`if condition do true else false end` is redundant. " <>
          "Use the condition directly — it already returns a boolean.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
