defmodule Credence.Pattern.NoDuplicateFunctionClauses do
  @moduledoc """
  Detects duplicate function clauses with identical argument patterns.

  In Elixir, a second clause whose argument patterns are structurally identical
  to an earlier clause is unreachable — the first clause always matches first.
  The compiler emits "this clause cannot match because a previous clause always
  matches" which blocks compilation under `--warnings-as-errors`.

  Two clauses have identical patterns when their arguments normalize to the same
  structure: bare variables are positionally equivalent regardless of name, and
  literal/structural patterns must match exactly.

  ## Bad

      defmodule Example do
        def bar(x, y), do: {x, y}
        def bar(x, y), do: {x, y}
      end

  ## Good

      defmodule Example do
        def bar(x, y), do: {x, y}
      end
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:__block__, _, stmts} = node, acc when is_list(stmts) ->
          new_issues = detect_duplicate_clauses(stmts) ++ acc
          {node, new_issues}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_ast_transform(ast, "", fn ast ->
      Macro.prewalk(ast, fn
        {:__block__, meta, stmts} when is_list(stmts) ->
          case strip_duplicate_clauses(stmts) do
            [single] -> single
            kept -> {:__block__, meta, kept}
          end

        node ->
          node
      end)
    end)
  end

  # Detect duplicate function clauses in a block of statements.
  defp detect_duplicate_clauses(stmts) do
    {_, issues} =
      Enum.reduce(stmts, {MapSet.new(), []}, fn
        {dt, _, _} = node, {seen, issues} when dt in [:def, :defp] ->
          case extract_clause_info(node) do
            {name, arity, args, guard} ->
              sig = {name, arity, normalize_args(args), guard}

              if MapSet.member?(seen, sig) do
                meta = elem(node, 1)
                issue = build_issue(meta, name, arity)
                {seen, [issue | issues]}
              else
                {MapSet.put(seen, sig), issues}
              end

            nil ->
              {seen, issues}
          end

        _node, acc ->
          acc
      end)

    issues
  end

  # Remove duplicate function clauses, keeping only the first of each signature.
  defp strip_duplicate_clauses(stmts) do
    {_, filtered} =
      Enum.reduce(stmts, {MapSet.new(), []}, fn
        {dt, _, _} = node, {seen, acc} when dt in [:def, :defp] ->
          case extract_clause_info(node) do
            {name, arity, args, guard} ->
              sig = {name, arity, normalize_args(args), guard}

              if MapSet.member?(seen, sig) do
                # Duplicate — drop it
                {seen, acc}
              else
                {MapSet.put(seen, sig), [node | acc]}
              end

            nil ->
              {seen, [node | acc]}
          end

        node, {seen, acc} ->
          {seen, [node | acc]}
      end)

    Enum.reverse(filtered)
  end

  # Extract {name, arity, args, guard} from a def/defp node.
  defp extract_clause_info({dt, _, [head | _]}) when dt in [:def, :defp] do
    case head do
      {:when, _, [{name, _, args} | guard_parts]} when is_atom(name) and is_list(args) ->
        {name, length(args), args, extract_guard(guard_parts)}

      {name, _, args} when is_atom(name) and is_list(args) ->
        {name, length(args), args, nil}

      _ ->
        nil
    end
  end

  defp extract_clause_info(_), do: nil

  # Extract a comparable guard representation from the guard parts.
  # After the `{:when, _, [head | guards]}` split, `guards` is a list of guard
  # expressions (for multi-guard `when g1, g2` it's a list; for a single guard
  # it's a single-element list).
  defp extract_guard([]), do: nil
  defp extract_guard([single]), do: normalize_ast(single)
  defp extract_guard(multi), do: Enum.map(multi, &normalize_ast/1)

  # Normalize arguments to a comparable form.
  # Bare variables are replaced with :_var so that `def bar(x, y)` and
  # `def bar(a, b)` compare as identical.
  defp normalize_args(args) do
    Enum.map(args, &normalize_ast/1)
  end

  # Recursively normalize an AST node, replacing variable names and stripping
  # positional metadata so that structurally identical clauses compare equal.
  defp normalize_ast({name, _, ctx}) when is_atom(name) and is_atom(ctx) do
    # Bare variable — normalize to a placeholder
    :_var
  end

  defp normalize_ast({form, _meta, args}) when is_list(args) do
    {form, Enum.map(args, &normalize_ast/1)}
  end

  defp normalize_ast({form, _meta, args}) when is_atom(args) do
    {form, args}
  end

  defp normalize_ast(other), do: other

  defp build_issue(meta, name, arity) do
    %Issue{
      rule: :no_duplicate_function_clauses,
      message:
        "Duplicate function clause for `#{name}/#{arity}`. " <>
          "The second clause has identical argument patterns and is unreachable.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
