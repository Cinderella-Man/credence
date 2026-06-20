defmodule Credence.Pattern.NoUnlessElse do
  @moduledoc """
  Detects `unless ... do ... else ... end` — a style guide violation.

  The Elixir style guide says: *"Never use `unless` with `else`.
  Rewrite these with the positive case first."*

  The fix swaps `unless` to `if` and reverses the branch bodies.
  The condition is never modified.

  ## Bad

      unless MapSet.member?(set, value) do
        :missing
      else
        :found
      end

  ## Good

      if MapSet.member?(set, value) do
        :found
      else
        :missing
      end

  ## Auto-fix

  Replaces `unless` with `if` and swaps the `do`/`else` bodies.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    if defines_unless?(ast) do
      []
    else
      {_ast, issues} =
        Macro.prewalk(ast, [], fn
          {:unless, meta, [_condition, clauses]} = node, acc ->
            if has_else?(clauses) do
              {node, [build_issue(meta) | acc]}
            else
              {node, acc}
            end

          node, acc ->
            {node, acc}
        end)

      Enum.reverse(issues)
    end
  end

  @impl true
  def fix_patches(ast, _opts) do
    if defines_unless?(ast) do
      []
    else
      Credence.RuleHelpers.patches_from_postwalk(ast, &maybe_rewrite/1)
    end
  end

  # A module may define its own `unless/2,3` (e.g. a query DSL like
  # `Explorer.Query`). Then `unless` is NOT `Kernel.unless`, and its `def`
  # head — `def unless(c, do: x, else: y)` — is itself shaped exactly like an
  # `unless cond, do:, else:` call. Rewriting either the head or in-module calls
  # to `if` breaks the DSL. If the file defines an `unless` function/macro,
  # leave every `unless` in it untouched.
  defp defines_unless?(ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        node, true ->
          {node, true}

        {dt, _, [{:unless, _, args} | _]} = node, false
        when dt in [:def, :defp, :defmacro, :defmacrop] and is_list(args) ->
          {node, true}

        {dt, _, [{:when, _, [{:unless, _, args} | _]} | _]} = node, false
        when dt in [:def, :defp, :defmacro, :defmacrop] and is_list(args) ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # Checks if a keyword list (from unless/if args) has an :else clause.
  defp has_else?(clauses) when is_list(clauses) do
    Enum.any?(clauses, fn
      {{:__block__, _, [:else]}, _} -> true
      _ -> false
    end)
  end

  defp has_else?(_), do: false

  # Rewrites a single unless...else node to if...else with swapped bodies.
  defp maybe_rewrite({:unless, meta, [condition, clauses]} = node) do
    if has_else?(clauses) do
      {:if, meta, [condition, swap_branches(clauses)]}
    else
      node
    end
  end

  defp maybe_rewrite(node), do: node

  # Swaps the do and else bodies in a keyword clause list.
  defp swap_branches(clauses) when is_list(clauses) do
    do_body = extract_clause(clauses, :do)
    else_body = extract_clause(clauses, :else)

    Enum.map(clauses, fn
      {{:__block__, m, [:do]}, _} -> {{:__block__, m, [:do]}, else_body}
      {{:__block__, m, [:else]}, _} -> {{:__block__, m, [:else]}, do_body}
      other -> other
    end)
  end

  # Extracts the body for a given clause key (:do or :else).
  defp extract_clause(clauses, key) do
    Enum.find_value(clauses, fn
      {{:__block__, _, [^key]}, body} -> body
      _ -> nil
    end)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_unless_else,
      message:
        "`unless` with `else` is a style violation. " <>
          "Rewrite as `if` with the branches swapped.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
