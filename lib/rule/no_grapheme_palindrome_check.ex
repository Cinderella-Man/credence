defmodule Credence.Rule.NoGraphemePalindromeCheck do
  @moduledoc """
  Readability & performance rule: Detects the pattern of decomposing a string
  into graphemes or a charlist, only to compare it with its own `Enum.reverse`.

  This pattern creates an unnecessary intermediate list. Use `String.reverse/1`
  and compare strings directly instead.

  ## Bad

      graphemes = String.graphemes(s)
      graphemes == Enum.reverse(graphemes)

      codepoints = String.to_charlist(s)
      codepoints == Enum.reverse(codepoints)

      normalized = s |> String.downcase() |> String.graphemes()
      normalized == Enum.reverse(normalized)

  ## Good

      cleaned = String.downcase(s)
      cleaned == String.reverse(cleaned)
  """

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    # Pass 1: collect variables bound to an expression ending in
    # String.graphemes/1 or String.to_charlist/1
    decompose_vars = collect_decompose_vars(ast)

    if MapSet.size(decompose_vars) == 0 do
      []
    else
      # Pass 2: find `var == Enum.reverse(var)` where var is in decompose_vars
      {_ast, issues} =
        Macro.prewalk(ast, [], fn
          # var == Enum.reverse(var)
          {:==, meta,
           [
             {var_name, _, nil},
             {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, [{var_name, _, nil}]}
           ]} = node,
          acc
          when is_atom(var_name) ->
            if MapSet.member?(decompose_vars, var_name) do
              {node, [build_issue(meta) | acc]}
            else
              {node, acc}
            end

          # Enum.reverse(var) == var (reversed comparison)
          {:==, meta,
           [
             {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, [{var_name, _, nil}]},
             {var_name, _, nil}
           ]} = node,
          acc
          when is_atom(var_name) ->
            if MapSet.member?(decompose_vars, var_name) do
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
  def fix(source, _opts) do
    ast = Sourceror.parse_string!(source)
    decompose_vars = collect_decompose_vars(ast)

    if MapSet.size(decompose_vars) == 0 do
      source
    else
      ast
      |> Macro.postwalk(fn
        # Strip decomposition from bindings:
        # graphemes = String.graphemes(s) → graphemes = s
        # normalized = s |> String.downcase() |> String.graphemes() → normalized = s |> String.downcase()
        {:=, meta, [{var_name, _, nil} = lhs, rhs]} when is_atom(var_name) ->
          if MapSet.member?(decompose_vars, var_name) do
            {:=, meta, [lhs, strip_decomposition(rhs)]}
          else
            {:=, meta, [lhs, rhs]}
          end

        # Replace Enum.reverse(var) → String.reverse(var) in == comparisons
        {:==, meta, [lhs, rhs]} ->
          {:==, meta,
           [
             maybe_replace_reverse(lhs, decompose_vars),
             maybe_replace_reverse(rhs, decompose_vars)
           ]}

        node ->
          node
      end)
      |> Sourceror.to_string()
    end
  end

  # ── Fix helpers ────────────────────────────────────────────────────

  # Strip the terminal String.graphemes/String.to_charlist from an expression
  defp strip_decomposition(rhs) do
    case rhs do
      # Piped chain ending in decomposition: ... |> String.graphemes()
      {:|>, _, [rest, rhs_call]} ->
        if decomposition_call?(rhs_call), do: rest, else: rhs

      # Direct decomposition call: String.graphemes(s) → s
      {{:., _, [{:__aliases__, _, [:String]}, func]}, _, [arg]}
      when func in [:graphemes, :to_charlist] ->
        arg

      _ ->
        rhs
    end
  end

  # Replace Enum.reverse(var) → String.reverse(var) for decompose vars
  defp maybe_replace_reverse(
         {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, [{var_name, _, nil} = var]},
         decompose_vars
       )
       when is_atom(var_name) do
    if MapSet.member?(decompose_vars, var_name) do
      {{:., [], [{:__aliases__, [], [:String]}, :reverse]}, [], [var]}
    else
      {{:., [], [{:__aliases__, [], [:Enum]}, :reverse]}, [], [var]}
    end
  end

  defp maybe_replace_reverse(node, _decompose_vars), do: node

  # ── Shared detection ───────────────────────────────────────────────

  # Collect variables bound to an expression ending in String.graphemes/to_charlist
  defp collect_decompose_vars(ast) do
    {_ast, vars} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:=, _, [{var_name, _, nil}, rhs]} = node, acc when is_atom(var_name) ->
          terminal = rightmost(rhs)

          if decomposition_call?(terminal) do
            {node, MapSet.put(acc, var_name)}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    vars
  end

  # Returns the rightmost (terminal) call in a pipe chain.
  defp rightmost({:|>, _, [_, right]}), do: rightmost(right)
  defp rightmost(other), do: other

  defp decomposition_call?(node) do
    match?(
      {{:., _, [{:__aliases__, _, [:String]}, func]}, _, _}
      when func in [:graphemes, :to_charlist],
      node
    )
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_grapheme_palindrome_check,
      message:
        "Avoid decomposing a string into graphemes/charlist just to compare with `Enum.reverse/1`. " <>
          "Use `str == String.reverse(str)` instead — it is clearer and avoids creating an intermediate list.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
