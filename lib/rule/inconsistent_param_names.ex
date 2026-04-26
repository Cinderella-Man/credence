defmodule Credence.Rule.InconsistentParamNames do
  @moduledoc """
  Detects functions where the same positional parameter uses different
  variable names across clauses.

  ## Why this matters

  LLMs generate function clauses semi-independently, often drifting
  parameter names between clauses of the same function:

      # Flagged — first arg is "current" in one clause, "prev" in another
      defp do_fibonacci(current, _next, 0), do: current
      defp do_fibonacci(prev, current, steps), do: do_fibonacci(current, prev + current, steps - 1)

      # Consistent — same name at each position across all clauses
      defp do_fibonacci(prev, _current, 0), do: prev
      defp do_fibonacci(prev, current, steps), do: do_fibonacci(current, prev + current, steps - 1)

  Inconsistent names make the reader question whether the function is
  correct — if the first argument is called `current` in one clause and
  `prev` in another, which is it?

  ## Detection scope (strict)

  Only simple variables are compared.  A position is **skipped** if
  any clause uses a pattern, literal, or underscore-prefixed variable
  at that position.  This avoids false positives on legitimate
  pattern-matching dispatch like:

      def handle({:ok, result}), do: result
      def handle({:error, reason}), do: raise reason

  Single-clause functions are never flagged.

  ## Severity

  `:warning`
  """

  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    clauses = collect_clauses(ast)

    clauses
    |> Enum.group_by(fn {name, arity, _args, _meta, _def_type} -> {name, arity} end)
    |> Enum.flat_map(fn {_key, group} -> analyze_group(group) end)
    |> Enum.sort_by(fn issue -> issue.meta[:line] || 0 end)
  end

  # ------------------------------------------------------------
  # CLAUSE COLLECTION
  # ------------------------------------------------------------

  defp collect_clauses(ast) do
    {_ast, clauses} =
      Macro.prewalk(ast, [], fn node, acc ->
        case extract_clause(node) do
          {:ok, clause} -> {node, [clause | acc]}
          :error -> {node, acc}
        end
      end)

    Enum.reverse(clauses)
  end

  # Guarded form must come first (same issue as NoUnderscoreFunctionName)
  defp extract_clause({def_type, meta, [{:when, _, [{fn_name, _, args}, _guard]}, _body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    {:ok, {fn_name, length(args), args, meta, def_type}}
  end

  defp extract_clause({def_type, meta, [{fn_name, _, args}, _body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    {:ok, {fn_name, length(args), args, meta, def_type}}
  end

  defp extract_clause(_), do: :error

  # ------------------------------------------------------------
  # GROUP ANALYSIS
  # ------------------------------------------------------------

  defp analyze_group(clauses) when length(clauses) < 2, do: []

  defp analyze_group(clauses) do
    [{name, arity, _, _, def_type} | _] = clauses
    args_lists = Enum.map(clauses, fn {_, _, args, _, _} -> args end)
    meta = clauses |> hd() |> elem(3)

    Enum.flat_map(0..(arity - 1), fn pos ->
      names_at_pos =
        args_lists
        |> Enum.map(fn args -> Enum.at(args, pos) end)
        |> Enum.map(&extract_simple_var/1)

      if Enum.any?(names_at_pos, &is_nil/1) do
        # At least one clause uses a pattern, literal, or underscore
        # at this position — skip to avoid false positives.
        []
      else
        unique_names = Enum.uniq(names_at_pos)

        if length(unique_names) > 1 do
          [build_issue(def_type, name, arity, pos + 1, unique_names, meta)]
        else
          []
        end
      end
    end)
  end

  # ------------------------------------------------------------
  # VARIABLE EXTRACTION
  #
  # Returns the atom name for simple, non-underscore variables.
  # Returns nil for everything else: patterns, literals, pins,
  # and underscore-prefixed names.  When any clause returns nil
  # for a position, that position is skipped entirely.
  # ------------------------------------------------------------

  defp extract_simple_var({name, _, ctx}) when is_atom(name) and is_atom(ctx) do
    str = Atom.to_string(name)

    if String.starts_with?(str, "_") do
      nil
    else
      name
    end
  end

  defp extract_simple_var(_), do: nil

  # ------------------------------------------------------------
  # MESSAGE GENERATION
  # ------------------------------------------------------------

  defp build_issue(def_type, name, arity, position, conflicting_names, meta) do
    %Issue{
      rule: :inconsistent_param_names,
      severity: :warning,
      message: build_message(def_type, name, arity, position, conflicting_names),
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp build_message(def_type, name, arity, position, conflicting_names) do
    names_str = conflicting_names |> Enum.map(&"`#{&1}`") |> Enum.join(", ")

    """
    Inconsistent parameter names in `#{def_type} #{name}/#{arity}` \
    at position #{position}: #{names_str}.

    Using different names for the same parameter across clauses makes \
    the code harder to follow. Choose one name and use it consistently, \
    or use `_` to indicate the parameter is unused in that clause.
    """
  end
end
