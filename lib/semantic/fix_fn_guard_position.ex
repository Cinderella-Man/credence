defmodule Credence.Semantic.FixFnGuardPosition do
  @moduledoc """
  Fixes `cannot find or invoke local when/2 inside a match` compile errors.

  LLMs repeatedly place `when` guards between fn-clause arguments (before the
  last arg) instead of after all arguments, producing compile errors like:

      "cannot find or invoke local when/2 inside a match. Only macros can be
      invoked inside a match and they must be defined before their invocation.
      Called as: {[second], count} when second > cutoff"

  The fix deterministically moves the `when` to after all arguments, preserving
  the guard expression and clause body.

  ## Before

      fn {key, val} when key > cutoff, acc -> acc + val end

  ## After

      fn {key, val}, acc when key > cutoff -> acc + val end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "cannot find or invoke local when/2 inside a match"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_fn_guard_position,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:fn, fn_meta, clauses}, acc ->
            {new_clauses, clauses_changed} =
              Enum.map_reduce(clauses, false, fn
                {:->, arrow_meta, [patterns, body]}, clause_acc
                when is_list(patterns) and length(patterns) > 1 ->
                  case find_misplaced_when(patterns) do
                    {:ok, when_idx} ->
                      new_patterns = move_when_after_all_patterns(patterns, when_idx)
                      {{:->, arrow_meta, [new_patterns, body]}, true}

                    :not_found ->
                      {{:->, arrow_meta, [patterns, body]}, clause_acc}
                  end

                clause, clause_acc ->
                  {clause, clause_acc}
              end)

            if clauses_changed do
              {{:fn, fn_meta, new_clauses}, true}
            else
              {{:fn, fn_meta, clauses}, acc}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # Find a `when` node in the patterns list that is NOT the last element.
  # In correct Elixir, `when` is always the last (and only) element wrapping
  # all patterns + the guard. A `when` among sibling patterns is misplaced.
  defp find_misplaced_when(patterns) do
    when_idx =
      Enum.find_index(patterns, fn
        {:when, _, _} -> true
        _ -> false
      end)

    case when_idx do
      nil -> :not_found
      idx when idx < length(patterns) - 1 -> {:ok, idx}
      _ -> :not_found
    end
  end

  # Move the misplaced `when` to wrap ALL patterns, with the guard last.
  #
  # Before: patterns = [before..., {:when, _, [inner_pat, guard]}, after...]
  # After:  patterns = [{:when, _, [before..., inner_pat, after..., guard]}]
  defp move_when_after_all_patterns(patterns, when_idx) do
    {before_when, [when_node | after_when]} = Enum.split(patterns, when_idx)
    {:when, when_meta, when_children} = when_node

    # Last child is the guard; everything before it is already-collected patterns
    {when_patterns, [guard]} = Enum.split(when_children, -1)

    # All patterns in source order, guard at the end
    all_patterns = before_when ++ when_patterns ++ after_when
    [{:when, when_meta, all_patterns ++ [guard]}]
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
