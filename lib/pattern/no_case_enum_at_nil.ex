defmodule Credence.Pattern.NoCaseEnumAtNil do
  @moduledoc """
  Detects `case Enum.at(list, n) do nil -> raise; v -> v end` that should
  use `Enum.fetch!/2`.

  LLMs frequently wrap `Enum.at/2` in a `case` to check for `nil` and raise
  when the index is out of bounds. This is exactly what `Enum.fetch!/2` does
  natively — and the manual version is subtly buggy: `Enum.at/2` returns
  `nil` both for out-of-bounds AND for a list that actually contains `nil`
  at that index, so the `case` falsely raises on legitimate `nil` elements.

  ## Bad

      case Enum.at(sublist, n) do
        nil -> raise ArgumentError, "Sublist is too short"
        element -> element
      end

  ## Good

      Enum.fetch!(sublist, n)

  ## Auto-fix

  None — the error type changes (ArgumentError → Enum.OutOfBoundsError)
  and the error message differs, so this is a check-only rule.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # case Enum.at(list, n) do ... end
        {:case, meta, [enum_call, kw]} = node, acc when is_list(kw) ->
          if enum_at_call?(enum_call) and nil_raise_or_error_clause?(extract_do_clauses(kw)) do
            {node, [build_issue(meta) | acc]}
          else
            {node, acc}
          end

        # expr |> case do ... end (single-arg case from pipe)
        {:|>, _, [enum_call, {:case, meta, [kw]}]} = node, acc when is_list(kw) ->
          if enum_at_call?(enum_call) and nil_raise_or_error_clause?(extract_do_clauses(kw)) do
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
  def fix_patches(_ast, _opts), do: []

  # Extract the clause list from a case node's keyword block.
  defp extract_do_clauses([{{:__block__, _, [:do]}, clauses}]) when is_list(clauses),
    do: clauses

  defp extract_do_clauses(_), do: nil

  # Matches Enum.at(list, n) — direct call or piped
  defp enum_at_call?({{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, _args}), do: true

  defp enum_at_call?({:|>, _, [_lhs, {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, _}]}),
    do: true

  defp enum_at_call?(_), do: false

  # Checks if the case clauses have:
  #   nil -> raise/error/tuple
  #   variable -> variable  (identity)
  defp nil_raise_or_error_clause?(nil), do: false

  defp nil_raise_or_error_clause?(clauses) when is_list(clauses) do
    case_body = extract_nil_clause(clauses)
    match_body = extract_match_clause_body(clauses)

    case {case_body, match_body} do
      {{:nil, error_body}, {:var, var_body}} ->
        raises_or_returns_error?(error_body) and identity_var?(var_body)

      _ ->
        false
    end
  end

  defp nil_raise_or_error_clause?(_), do: false

  # Extract the nil clause body
  defp extract_nil_clause(clauses) do
    Enum.find_value(clauses, fn
      {:->, _, [[{:__block__, _, [nil]}], body]} -> {:nil, body}
      {:->, _, [[nil], body]} -> {:nil, body}
      _ -> nil
    end)
  end

  # Extract the catch-all/variable clause
  defp extract_match_clause_body(clauses) do
    Enum.find_value(clauses, fn
      {:->, _, [[{:_, _, _}], body]} -> {:var, body}
      {:->, _, [[{:__block__, _, [{name, _, ctx}]}], body]}
      when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) ->
        {:var, body}

      {:->, _, [[{name, _, ctx}], body]}
      when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) ->
        {:var, body}

      _ ->
        nil
    end)
  end

  # Checks if body raises
  defp raises_or_returns_error?({:raise, _, _}), do: true
  defp raises_or_returns_error?({:__block__, _, stmts}), do: Enum.any?(stmts, &raises_or_returns_error?/1)
  defp raises_or_returns_error?(_), do: false

  # Checks if the variable clause is an identity: v -> v
  defp identity_var?({name, _, ctx}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)), do: true
  defp identity_var?({:__block__, _, [{name, _, ctx}]}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)), do: true
  defp identity_var?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :no_case_enum_at_nil,
      message:
        "`case Enum.at(list, n) do nil -> raise; v -> v end` reimplements " <>
          "`Enum.fetch!/2`. Use `Enum.fetch!/2` — it is more idiomatic and " <>
          "avoids false positives when the list contains `nil` at that index.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
