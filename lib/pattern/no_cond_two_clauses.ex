defmodule Credence.Pattern.NoCondTwoClauses do
  @moduledoc """
  Detects `cond` with exactly two clauses where the second guard is
  `true` — a pattern that is just an `if/else` in disguise.

  ## Bad

      cond do
        low > high -> false
        true ->
          mid = div(low + high, 2)
          search(mid, target)
      end

  ## Good

      if low > high do
        false
      else
        mid = div(low + high, 2)
        search(mid, target)
      end

  ## Auto-fix

  Rewrites as `if/else` using the first clause's guard as the
  condition. The condition is never modified.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  # ── Check ─────────────────────────────────────────────────────────

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:cond, meta, _} = node, acc ->
          if two_clause_cond?(node) do
            {node, [build_issue(meta) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  # ── Fix ───────────────────────────────────────────────────────────

  @impl true
  def fix(source, _opts) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        if has_fixable?(ast) do
          ast
          |> Macro.postwalk(&maybe_rewrite/1)
          |> Sourceror.to_string()
        else
          source
        end

      {:error, _} ->
        source
    end
  end

  # ── Detection ────────────────────────────────────────────────────

  # Checks if a cond node has exactly 2 clauses with `true` as
  # the second guard.
  defp two_clause_cond?({:cond, _, [kw]}) when is_list(kw) do
    case extract_do_clauses(kw) do
      [_first, second] -> guard_is_true?(second)
      _ -> false
    end
  end

  defp two_clause_cond?(_), do: false

  # Extracts the list of arrow clauses from the cond's keyword args.
  # Handles both Code.string_to_quoted and Sourceror forms.
  defp extract_do_clauses(kw) do
    Enum.find_value(kw, fn
      {:do, clauses} when is_list(clauses) -> clauses
      {{:__block__, _, [:do]}, clauses} when is_list(clauses) -> clauses
      _ -> nil
    end)
  end

  # Checks if an arrow clause has `true` as its guard.
  defp guard_is_true?({:->, _, [[guard], _body]}) do
    match_true?(guard)
  end

  defp guard_is_true?(_), do: false

  defp match_true?(true), do: true
  defp match_true?({:__block__, _, [true]}), do: true
  defp match_true?(_), do: false

  # ── Pre-scan ─────────────────────────────────────────────────────

  defp has_fixable?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        _node, true ->
          {nil, true}

        {:cond, _, _} = node, false ->
          {node, two_clause_cond?(node)}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # ── Fix: node rewriting ──────────────────────────────────────────

  defp maybe_rewrite({:cond, meta, [kw]} = node) when is_list(kw) do
    case extract_do_clauses(kw) do
      [first, second] ->
        if guard_is_true?(second) do
          rewrite_to_if(meta, first, second, kw)
        else
          node
        end

      _ ->
        node
    end
  end

  defp maybe_rewrite(node), do: node

  # Builds an if/else node from the two cond clauses.
  defp rewrite_to_if(meta, first_clause, second_clause, original_kw) do
    {:->, _, [[condition], do_body]} = first_clause
    {:->, _, [[_true], else_body]} = second_clause

    if_clauses = build_if_clauses(original_kw, do_body, else_body)
    {:if, meta, [condition, if_clauses]}
  end

  # Builds the keyword list for the if node, preserving the
  # keyword format (bare or __block__-wrapped) from the original cond.
  defp build_if_clauses(original_kw, do_body, else_body) do
    case hd(original_kw) do
      {{:__block__, do_meta, [:do]}, _} ->
        [
          {{:__block__, do_meta, [:do]}, do_body},
          {{:__block__, do_meta, [:else]}, else_body}
        ]

      {:do, _} ->
        [do: do_body, else: else_body]
    end
  end

  # ── Issue construction ───────────────────────────────────────────

  defp build_issue(meta) do
    %Issue{
      rule: :no_cond_two_clauses,
      message:
        "`cond` with two clauses where the second guard is `true` " <>
          "is an `if/else` in disguise. Use `if/else` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
