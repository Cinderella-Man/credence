defmodule Credence.Pattern.PreferNegateIfTrueFalse do
  @moduledoc """
  Detects `if cond do false else body end` and rewrites it to
  `if !cond do body end`.

  ## Why this matters

  The pattern `if cond do false else body end` is non-idiomatic Elixir.
  When the `do` branch is just `false`, negate the condition and keep
  only the non-false body.

  ## Bad

      if MapSet.member?(seen, current) do
        false
      else
        MapSet.put(seen, current)
        |> loop(sum_of_squared_digits(current))
      end

  ## Good

      if !MapSet.member?(seen, current) do
        MapSet.put(seen, current)
        |> loop(sum_of_squared_digits(current))
      end

  ## Auto-fix

  Negates the condition and moves the else body to the do branch,
  removing the else branch entirely.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:if, meta, [condition, branches]} = node, acc ->
          if anti_pattern?(condition, branches) do
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
    {_ast, patches} =
      Macro.prewalk(ast, [], fn
        {:if, if_meta, [condition, branches]} = node, acc ->
          if anti_pattern?(condition, branches) do
            else_body = extract_clause(branches, :else)
            rendered_else = Sourceror.to_string(else_body)

            # Patch 1: Negate the condition, wrapping in parens if binary op
            cond_range = Sourceror.get_range(condition)

            negate_patches =
              if binary_op?(condition) do
                # ! binds tighter than binary operators, so we need parens
                cond_end = cond_range.end

                [
                  %{
                    range: %{start: cond_end, end: cond_end},
                    change: ")"
                  },
                  %{
                    range: %{start: cond_range.start, end: cond_range.start},
                    change: "!("
                  }
                ]
              else
                [
                  %{
                    range: %{start: cond_range.start, end: cond_range.start},
                    change: "!"
                  }
                ]
              end

            # Patch 2: Replace from do keyword to end with new do block
            do_pos = if_meta[:do]
            end_pos = if_meta[:end]
            do_start = [line: do_pos[:line], column: do_pos[:column]]
            # end keyword is 3 chars, so we need to extend past column 1
            end_start = [line: end_pos[:line], column: end_pos[:column] + 3]

            # Get the indentation from the else body
            else_range = Sourceror.get_range(else_body)
            indent = else_range.start[:column] - 1
            indent_str = String.duplicate(" ", indent)

            # Indent each line of the rendered else body
            indented_else =
              rendered_else
              |> String.split("\n")
              |> Enum.map_join("\n", fn line ->
                if String.trim(line) == "", do: "", else: indent_str <> line
              end)

            new_do_block = "do\n#{indented_else}\nend"

            body_patch = %{
              range: %{start: do_start, end: end_start},
              change: new_do_block
            }

            {node, [body_patch | negate_patches ++ acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(patches)
  end

  # Check if a node is a binary operation that needs parentheses when negated.
  # ! binds tighter than binary operators, so !a OP b parses as (!a) OP b.
  defp binary_op?({op, _meta, [_left, _right]}) when is_atom(op) do
    op in [
      :==, :!=, :===, :!==, :=~,
      :<, :>, :<=, :>=,
      :+, :-, :*, :/, :div, :rem,
      :<>, :++, :--,
      :and, :or, :&&, :||,
      :.., :in, :"not in",
      :|>, :<<<, :>>>,
      :"~>>", :"<<~", :"~>", :"<~", :"<|>", :"<~>"
    ]
  end

  defp binary_op?(_), do: false

  # Returns true when the if matches: do branch is `false`, else branch exists.
  defp anti_pattern?(_condition, branches) when is_list(branches) do
    do_body = extract_clause(branches, :do)
    else_body = extract_clause(branches, :else)

    false_literal?(do_body) and else_body != nil
  end

  defp anti_pattern?(_, _), do: false

  # Check if a node is the literal `false`.
  defp false_literal?({:__block__, _, [false]}), do: true
  defp false_literal?(_), do: false

  # Extract the body for a given clause key (:do or :else).
  defp extract_clause(clauses, key) do
    Enum.find_value(clauses, fn
      {{:__block__, _, [^key]}, body} -> body
      _ -> nil
    end)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_negate_if_true_false,
      message:
        "`if cond do false else body end` is non-idiomatic. " <>
          "Negate the condition: `if !cond do body end`.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
