defmodule Credence.Pattern.NoGraphemePalindromeCheck do
  @moduledoc """
  Readability & performance rule: Detects the pattern of decomposing a string
  into graphemes or a charlist, only to compare it with its own `Enum.reverse`.

  This pattern creates an unnecessary intermediate list. Use `String.reverse/1`
  and compare strings directly instead.

  Detects `String.graphemes/1` or `String.to_charlist/1` at any position in a
  pipe chain — including mid-pipe when followed by `Enum.filter` or similar.
  Also detects the `case` variant where the result is destructured with an
  empty-list guard clause.

  ## Bad

      graphemes = String.graphemes(s)
      graphemes == Enum.reverse(graphemes)

      codepoints = String.to_charlist(s)
      codepoints == Enum.reverse(codepoints)

      normalized = s |> String.downcase() |> String.graphemes()
      normalized == Enum.reverse(normalized)

      cleaned = s |> String.downcase() |> String.graphemes() |> Enum.filter(fn c -> ... end)
      cleaned == Enum.reverse(cleaned)

      case String.to_charlist(s) do
        [] -> true
        chars -> chars == Enum.reverse(chars)
      end

  ## Good

      cleaned = String.downcase(s)
      cleaned == String.reverse(cleaned)

      s == String.reverse(s)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    check_assignment_pattern(ast) ++ check_case_pattern(ast)
  end

  # Pass 1: detect `var = String.graphemes(s); var == Enum.reverse(var)` form
  defp check_assignment_pattern(ast) do
    decompose_vars = collect_decompose_vars(ast)

    if map_size(decompose_vars) == 0 do
      []
    else
      safe_vars = filter_solely_palindrome_vars(decompose_vars, ast)

      if map_size(safe_vars) == 0 do
        []
      else
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
              if Map.has_key?(safe_vars, var_name) do
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
              if Map.has_key?(safe_vars, var_name) do
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
  end

  # Pass 2: detect `case String.to_charlist(s) do [] -> true; v -> v == Enum.reverse(v) end`
  defp check_case_pattern(ast) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:case, meta, [subject, [{{:__block__, _, [:do]}, clauses_block}]]} = node, acc ->
          case unwrap_clause_block(clauses_block) do
            [_ | _] = clauses ->
              if decompose_subject?(subject) and case_palindrome_pattern?(clauses) do
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

  @impl true
  def fix_patches(ast, _opts) do
    fix_assignment_pattern(ast) ++ fix_case_pattern(ast)
  end

  defp fix_assignment_pattern(ast) do
    decompose_vars = collect_decompose_vars(ast)
    safe_vars = filter_solely_palindrome_vars(decompose_vars, ast)

    terminal_var_names =
      safe_vars
      |> Enum.filter(fn {_, v} -> v == :terminal end)
      |> MapSet.new(fn {k, _} -> k end)

    if MapSet.size(terminal_var_names) == 0 do
      []
    else
      RuleHelpers.patches_from_postwalk(ast, fn
        {:=, meta, [{var_name, _, nil} = lhs, rhs]} when is_atom(var_name) ->
          if MapSet.member?(terminal_var_names, var_name) do
            {:=, meta, [lhs, strip_decomposition(rhs)]}
          else
            {:=, meta, [lhs, rhs]}
          end

        {:==, meta, [lhs, rhs]} ->
          {:==, meta,
           [
             maybe_replace_reverse(lhs, terminal_var_names),
             maybe_replace_reverse(rhs, terminal_var_names)
           ]}

        node ->
          node
      end)
    end
  end

  # Auto-fix for case-based palindrome: only when subject is a direct call
  # (not a pipe chain), replace with `subject == String.reverse(subject)`.
  defp fix_case_pattern(ast) do
    RuleHelpers.patches_from_postwalk(ast, fn
      {:case, _meta, [subject, [{{:__block__, _, [:do]}, clauses_block}]]} = node ->
        case unwrap_clause_block(clauses_block) do
          [_ | _] = clauses ->
            if decompose_subject?(subject) and case_palindrome_pattern?(clauses) do
              case direct_decompose_subject(subject) do
                {:ok, arg} ->
                  {:==, [], [arg, string_reverse_call(arg)]}

                :error ->
                  node
              end
            else
              node
            end

          _ ->
            node
        end

      node ->
        node
    end)
  end

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

  # Filter decompose_vars to only those used EXCLUSIVELY in the assignment and
  # the palindrome comparison. If the variable is used elsewhere (e.g. Enum.all?),
  # the decomposition is necessary and the rule must not fire.
  #
  # Uses a manual recursive walk (not Macro.prewalk) so we can skip children
  # of palindrome `==` nodes — prewalk would still descend into them.
  defp filter_solely_palindrome_vars(decompose_vars, ast) do
    if map_size(decompose_vars) == 0 do
      decompose_vars
    else
      extra = collect_extra_refs(decompose_vars, ast, MapSet.new())
      Map.drop(decompose_vars, MapSet.to_list(extra))
    end
  end

  defp collect_extra_refs(vars, node, acc) when is_list(node) do
    Enum.reduce(node, acc, fn child, a -> collect_extra_refs(vars, child, a) end)
  end

  defp collect_extra_refs(vars, node, acc) when is_tuple(node) do
    case node do
      # Assignment binding — skip LHS (it's the definition), walk RHS
      {:=, _, [{var_name, _, nil}, rhs]} when is_atom(var_name) ->
        if Map.has_key?(vars, var_name),
          do: collect_extra_refs(vars, rhs, acc),
          else: walk_children(vars, node, acc)

      # Palindrome comparison: var == Enum.reverse(var) — skip entirely
      {:==, _,
       [
         {var_name, _, nil},
         {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, [{var_name2, _, nil}]}
       ]}
      when is_atom(var_name) and is_atom(var_name2) and var_name == var_name2 ->
        if Map.has_key?(vars, var_name), do: acc, else: walk_children(vars, node, acc)

      # Reversed: Enum.reverse(var) == var — skip entirely
      {:==, _,
       [
         {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, [{var_name2, _, nil}]},
         {var_name, _, nil}
       ]}
      when is_atom(var_name) and is_atom(var_name2) and var_name == var_name2 ->
        if Map.has_key?(vars, var_name), do: acc, else: walk_children(vars, node, acc)

      # Reference to a decompose var in any other context
      {var_name, _, nil} when is_atom(var_name) ->
        if Map.has_key?(vars, var_name),
          do: MapSet.put(acc, var_name),
          else: acc

      # Any other node — walk children
      _ ->
        walk_children(vars, node, acc)
    end
  end

  defp collect_extra_refs(_vars, _node, acc), do: acc

  defp walk_children(vars, node, acc) do
    node
    |> Tuple.to_list()
    |> Enum.reduce(acc, fn child, a -> collect_extra_refs(vars, child, a) end)
  end

  # Collect variables bound to an expression containing String.graphemes/to_charlist.
  # Returns %{var_name => :terminal} when graphemes is the rightmost pipe call,
  # or %{var_name => :non_terminal} when graphemes appears earlier in the chain.
  defp collect_decompose_vars(ast) do
    {_ast, vars} =
      Macro.prewalk(ast, %{}, fn
        {:=, _, [{var_name, _, nil}, rhs]} = node, acc when is_atom(var_name) ->
          terminal = rightmost(rhs)

          cond do
            decomposition_call?(terminal) ->
              {node, Map.put(acc, var_name, :terminal)}

            has_decomposition_in_chain?(rhs) ->
              {node, Map.put(acc, var_name, :non_terminal)}

            true ->
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

  # Returns true if String.graphemes/to_charlist appears anywhere in the pipe chain.
  defp has_decomposition_in_chain?({:|>, _, [left, right]}) do
    decomposition_call?(right) or has_decomposition_in_chain?(left)
  end

  defp has_decomposition_in_chain?(node), do: decomposition_call?(node)

  defp build_issue(meta) do
    %Issue{
      rule: :no_grapheme_palindrome_check,
      message:
        "Avoid decomposing a string into graphemes/charlist just to compare with `Enum.reverse/1`. " <>
          "Use `str == String.reverse(str)` instead — it is clearer and avoids creating an intermediate list.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  # ── Case-based palindrome pattern helpers ──

  defp case_palindrome_pattern?(clauses) do
    clause_list = unwrap_clause_block(clauses)

    case clause_list do
      [clause1, clause2] ->
        (empty_clause?(clause1) and var_reverse_clause?(clause2)) or
          (empty_clause?(clause2) and var_reverse_clause?(clause1))

      _ ->
        false
    end
  end

  defp unwrap_clause_block({:__block__, _, list}), do: list
  defp unwrap_clause_block(list) when is_list(list), do: list

  # Empty list pattern — may be bare or block-wrapped by Sourceror
  # Body may also be wrapped: true or {:__block__, _, [true]}
  defp empty_clause?({:->, _, [[{:__block__, _, [[]]}], body]}), do: literal_true?(body)
  defp empty_clause?({:->, _, [[[]], body]}), do: literal_true?(body)
  defp empty_clause?(_), do: false

  defp literal_true?(true), do: true
  defp literal_true?({:__block__, _, [true]}), do: true
  defp literal_true?(_), do: false

  # Variable pattern — may be bare or block-wrapped by Sourceror
  defp var_reverse_clause?({:->, _, [[{:__block__, _, [{var_name, _, nil}]}], body]})
       when is_atom(var_name),
       do: reverse_comparison?(var_name, body)

  defp var_reverse_clause?({:->, _, [[{var_name, _, nil}], body]})
       when is_atom(var_name),
       do: reverse_comparison?(var_name, body)

  defp var_reverse_clause?(_), do: false

  # var == Enum.reverse(var) or var == (var |> Enum.reverse())
  defp reverse_comparison?(var, {:==, _, [{v, _, nil}, rhs]}) when is_atom(v) and v == var do
    enum_reverse_of?(var, rhs)
  end

  # Enum.reverse(var) == var or (var |> Enum.reverse()) == var
  defp reverse_comparison?(var, {:==, _, [lhs, {v, _, nil}]}) when is_atom(v) and v == var do
    enum_reverse_of?(var, lhs)
  end

  defp reverse_comparison?(_, _), do: false

  # Enum.reverse(var) — direct call form
  defp enum_reverse_of?(
         var,
         {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, [{v, _, nil}]}
       )
       when is_atom(v) and v == var,
       do: true

  # var |> Enum.reverse() — pipe form (Sourceror preserves the pipe)
  defp enum_reverse_of?(
         var,
         {:|>, _, [{v, _, nil}, {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, []}]}
       )
       when is_atom(v) and v == var,
       do: true

  defp enum_reverse_of?(_, _), do: false

  # Check if a case subject is a String.to_charlist/graphemes call (direct or piped)
  defp decompose_subject?({{:., _, [{:__aliases__, _, [:String]}, func]}, _, _})
       when func in [:to_charlist, :graphemes],
       do: true

  defp decompose_subject?({:|>, _, _} = pipe) do
    case rightmost(pipe) do
      {{:., _, [{:__aliases__, _, [:String]}, func]}, _, _} when func in [:to_charlist, :graphemes] -> true
      _ -> false
    end
  end

  defp decompose_subject?(_), do: false

  # Extract subject from a direct String.to_charlist/graphemes call (not piped)
  defp direct_decompose_subject(
         {{:., _, [{:__aliases__, _, [:String]}, func]}, _, [arg]}
       )
       when func in [:to_charlist, :graphemes],
       do: {:ok, arg}

  defp direct_decompose_subject(_), do: :error

  defp string_reverse_call(arg) do
    {{:., [], [{:__aliases__, [], [:String]}, :reverse]}, [], [arg]}
  end
end
