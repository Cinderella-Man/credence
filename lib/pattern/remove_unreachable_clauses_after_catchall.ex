defmodule Credence.Pattern.RemoveUnreachableClausesAfterCatchall do
  @moduledoc """
  Detects function clauses that follow a catch-all (bare variables / underscores,
  no guard) and are therefore unreachable at runtime.

  A catch-all clause matches every call, so any clause placed after it will
  never execute. This triggers the compiler warning
  "this clause cannot match because a previous clause at line N always matches"
  which blocks compilation when `--warnings-as-errors` is active.

  ## Bad

      defmodule Solution do
        def exactly_one_replace([], []), do: false
        def exactly_one_replace([h1 | t1], [h2 | t2]) when h1 == h2 do
          exactly_one_replace(t1, t2)
        end
        def exactly_one_replace(t1, t2) do
          t1 == t2
        end
        def exactly_one_replace(_, _), do: false  # unreachable!
      end

  ## Good

      defmodule Solution do
        def exactly_one_replace([], []), do: false
        def exactly_one_replace([h1 | t1], [h2 | t2]) when h1 == h2 do
          exactly_one_replace(t1, t2)
        end
        def exactly_one_replace(t1, t2) do
          t1 == t2
        end
      end

  ## Auto-fix

  Removes every clause that follows the first catch-all clause in each
  consecutive group of `def`/`defp` clauses sharing the same name and arity.
  The catch-all clause itself is preserved — it is the clause that handles
  all remaining inputs.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    ast
    |> extract_def_groups()
    |> Enum.flat_map(fn {_key, clauses} ->
      case find_unreachable_after_catchall(clauses) do
        {_, []} ->
          []

        {catchall, unreachable} ->
          catchall_line = elem(catchall, 3) |> Keyword.get(:line)
          Enum.map(unreachable, &build_issue(&1, catchall_line))
      end
    end)
  end

  @impl true
  def fix_patches(ast, _opts) do
    # Emit a DELETE patch over each unreachable clause's own source range.
    # Re-rendering the whole module (the previous `patches_from_ast_transform`
    # approach) left the surviving nodes with stale Sourceror positions, so the
    # render swallowed the module's closing `end` and produced non-compiling
    # output that was reverted. Deleting exact ranges touches nothing else.
    {_ast, patches} =
      Macro.prewalk(ast, [], fn
        {:__block__, _meta, stmts} = node, acc when is_list(stmts) ->
          {node, block_patches(stmts) ++ acc}

        node, acc ->
          {node, acc}
      end)

    patches
  end

  # Per consecutive same-name/arity group, either:
  #  - DELETE unreachable clauses when they are all guard-less (existing behaviour), or
  #  - MOVE the catch-all to the end when any unreachable clause has a guard,
  #    so the guarded clause becomes reachable (over_fire fix).
  defp block_patches(stmts) do
    stmts
    |> filter_def_nodes()
    |> Enum.chunk_by(fn {name, arity, _, _, _} -> {name, arity} end)
    |> Enum.flat_map(fn group ->
      case find_unreachable_in_group(group) do
        {_catchall, []} ->
          []

        {catchall, unreachable} ->
          if any_have_guards?(unreachable) do
            move_catchall_to_end(catchall, unreachable)
          else
            delete_unreachable_patches(catchall, unreachable)
          end
      end
    end)
  end

  # Delete one merged range from END of catch-all through END of last unreachable
  # clause — existing behaviour for guard-less unreachable clauses.
  defp delete_unreachable_patches(catchall, unreachable) do
    catchall_end = Sourceror.get_range(elem(catchall, 4)).end
    last_end = unreachable |> List.last() |> elem(4) |> Sourceror.get_range() |> Map.get(:end)
    [%{range: %{start: catchall_end, end: last_end}, change: ""}]
  end

  # Move the catch-all clause to the end of the group so guarded clauses
  # become reachable. Two patches: delete the catch-all (and blank lines before
  # the first unreachable), then insert it after the last unreachable clause.
  defp move_catchall_to_end(catchall, unreachable) do
    catchall_node = elem(catchall, 4)
    catchall_range = Sourceror.get_range(catchall_node)
    catchall_source = Sourceror.to_string(catchall_node)

    first_unreachable_range = unreachable |> hd() |> elem(4) |> Sourceror.get_range()
    last_unreachable_range = unreachable |> List.last() |> elem(4) |> Sourceror.get_range()

    [
      # Delete the catch-all clause and trailing blank lines up to the first unreachable
      %{range: %{start: catchall_range.start, end: first_unreachable_range.start}, change: ""},
      # Insert the catch-all after the last unreachable clause
      %{
        range: %{start: last_unreachable_range.end, end: last_unreachable_range.end},
        change: "\n\n" <> catchall_source
      }
    ]
  end

  defp any_have_guards?(clauses) do
    Enum.any?(clauses, fn {_, _, _, _, node} -> has_guard?(node) end)
  end

  defp has_guard?({dt, _, [{:when, _, _} | _]}) when dt in [:def, :defp], do: true
  defp has_guard?(_), do: false

  # Walk the AST and extract def/defp groups for analysis (used by check/2).
  defp extract_def_groups({:defmodule, _meta, [_alias, kw]}) when is_list(kw) do
    case Credence.RuleHelpers.extract_do_body(kw) do
      {:ok, {:__block__, _, defs}} ->
        defs
        |> filter_def_nodes()
        |> Enum.chunk_by(fn {name, arity, _, _, _} -> {name, arity} end)
        |> Enum.map(fn group ->
          key = group |> hd() |> then(fn {n, a, _, _, _} -> {n, a} end)
          {key, group}
        end)

      _ ->
        []
    end
  end

  defp extract_def_groups(_), do: []

  # Filter and annotate def/defp nodes from a list of AST statements.
  #
  # Only clauses *with a body* are real clauses. A bodiless head
  # (`def code(integer_or_atom)` — the 1-element `[head]` form used to declare
  # default args / attach docs) generates no runtime clause and matches nothing,
  # so it must never be treated as a catch-all (or as an unreachable clause).
  defp filter_def_nodes(stmts) do
    Enum.flat_map(stmts, fn
      {dt, meta, [head, _body]} = node when dt in [:def, :defp] ->
        name = extract_name(head)
        args = extract_args(head)
        [{name, length(args), dt, meta, node}]

      _ ->
        []
    end)
  end

  # Given a group of clauses for the same function, return the catch-all
  # and the list of unreachable clauses (those after it).
  defp find_unreachable_in_group(clauses) do
    case Enum.find_index(clauses, fn {_, _, _, _, node} -> catch_all?(node) end) do
      nil ->
        {nil, []}

      idx ->
        {Enum.at(clauses, idx), Enum.drop(clauses, idx + 1)}
    end
  end

  defp find_unreachable_after_catchall(clauses) do
    find_unreachable_in_group(clauses)
  end

  # A catch-all clause has only bare variables or underscores as arguments,
  # no guard, and no repeated variable name. A repeated name (other than the
  # bare `_`) is a non-linear pattern that imposes an equality constraint
  # (`def f(x, x)`, `defp split_key(_b, start, start)`) — it matches only when
  # those args are equal, so it is NOT a catch-all and clauses after it stay
  # reachable.
  defp catch_all?({dt, _, [head | _]}) when dt in [:def, :defp] do
    case head do
      {:when, _, _} ->
        false

      {_, _, args} when is_list(args) ->
        args != [] and Enum.all?(args, &bare_var_or_underscore?/1) and
          not repeated_named_var?(args)

      _ ->
        false
    end
  end

  defp catch_all?(_), do: false

  # True if any non-`_` variable name appears more than once in the arg list.
  defp repeated_named_var?(args) do
    names =
      Enum.flat_map(args, fn
        {:_, _, ctx} when is_atom(ctx) -> []
        {name, _, ctx} when is_atom(name) and is_atom(ctx) -> [name]
        _ -> []
      end)

    names != Enum.uniq(names)
  end

  defp bare_var_or_underscore?({:_, _, ctx}) when is_atom(ctx), do: true

  defp bare_var_or_underscore?({name, _, ctx})
       when is_atom(name) and is_atom(ctx),
       do: true

  defp bare_var_or_underscore?(_), do: false

  # Extract function name from a def head (with or without guard).
  defp extract_name({:when, _, [{name, _, _} | _]}) when is_atom(name), do: name
  defp extract_name({name, _, _}) when is_atom(name), do: name
  defp extract_name(_), do: nil

  # Extract args from a def head (with or without guard).
  defp extract_args({:when, _, [inner | _]}), do: extract_args(inner)
  defp extract_args({_, _, args}) when is_list(args), do: args
  defp extract_args(_), do: []

  defp build_issue({_, _, dt, meta, _node}, catchall_line) do
    line = Keyword.get(meta, :line)

    %Issue{
      rule: :remove_unreachable_clauses_after_catchall,
      message:
        "This `#{dt}` clause is unreachable because a preceding catch-all clause " <>
          "(at line #{catchall_line}) always matches. Remove this clause to fix the " <>
          "compiler warning.",
      meta: %{line: line}
    }
  end
end
