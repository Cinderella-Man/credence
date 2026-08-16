defmodule Credence.Pattern.RemoveUnreachableClausesAfterCatchall do
  @moduledoc """
  Removes a redundant duplicate catch-all clause — a bare catch-all clause
  (all arguments bare variables / underscores, no guard) that follows an
  earlier catch-all clause for the same name and arity and is therefore
  unreachable at runtime.

  The first catch-all already matches every call, so any later catch-all can
  never execute. This triggers the compiler warning "this clause cannot match
  because a previous clause at line N always matches", which blocks compilation
  under `--warnings-as-errors`. Because both clauses match the *exact same*
  domain (every input of that arity), the later one is provably dead code that
  no reordering could ever make reachable — so removing it preserves behaviour
  on every input.

  ## Bad

      defmodule SolutionRUCAC do
        def exactly_one_replace([], []), do: false
        def exactly_one_replace([h1 | t1], [h2 | t2]) when h1 == h2 do
          exactly_one_replace(t1, t2)
        end
        def exactly_one_replace(t1, t2) do
          t1 == t2
        end
        def exactly_one_replace(_, _), do: false  # unreachable duplicate catch-all!
      end

  ## Good

      defmodule SolutionRUCAC do
        def exactly_one_replace([], []), do: false
        def exactly_one_replace([h1 | t1], [h2 | t2]) when h1 == h2 do
          exactly_one_replace(t1, t2)
        end
        def exactly_one_replace(t1, t2) do
          t1 == t2
        end
      end

  ## What it deliberately does NOT touch

  A clause that is unreachable only because of its *position* — a guarded clause
  or a clause with a literal/structural pattern placed after a catch-all — is
  left alone. Such a clause matches a *narrower* domain than the catch-all, so
  it is dead only because the author ordered the clauses wrongly; removing it
  (or reordering, which changes dispatch) would silently change the program's
  behaviour or mask a real bug. Only a duplicate catch-all — which can never
  express any distinct behaviour — is safe to delete, so that is all this rule
  removes.

  A clause with a *dynamic* head name (`def unquote(op)(a, b)`, generated inside
  a macro) is also left alone: its name is only known at expansion time, so
  distinct functions would otherwise collapse into one `{nil, arity}` group and
  a live clause could be deleted as a phantom duplicate.

  ## Auto-fix

  Deletes each catch-all clause that follows the first catch-all in a consecutive
  group of `def`/`defp` clauses sharing the same name and arity, but only when
  *every* clause after the first catch-all is itself a bare catch-all. The first
  catch-all is preserved — it is the clause that handles all inputs.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    ast
    |> collect_groups()
    |> Enum.flat_map(fn {catchall, unreachable} ->
      catchall_line = catchall |> elem(3) |> Keyword.get(:line)
      Enum.map(unreachable, &build_issue(&1, catchall_line))
    end)
  end

  @impl true
  def fix_patches(ast, _opts) do
    # Emit one DELETE patch per fixable group, over the exact source range from
    # the END of the catch-all through the END of the last redundant catch-all.
    # Re-rendering the whole module left surviving nodes with stale Sourceror
    # positions (the render swallowed the module's closing `end` and produced
    # non-compiling output that was reverted); deleting exact ranges touches
    # nothing else.
    ast
    |> collect_groups()
    |> Enum.map(&delete_patch/1)
  end

  # Walk every block in the module(s) and return the `{catchall, unreachable}`
  # groups that are SAFE to fix: a catch-all clause followed ONLY by further
  # bare catch-all clauses (redundant duplicates). `check` and `fix` both drive
  # off this one function so they can never disagree. Groups whose post-catch-all
  # clauses include a guard or a pattern are dropped here — see the moduledoc.
  defp collect_groups(ast) do
    {_ast, groups} =
      Macro.prewalk(ast, [], fn
        {:__block__, _meta, stmts} = node, acc when is_list(stmts) ->
          {node, acc ++ block_groups(stmts)}

        node, acc ->
          {node, acc}
      end)

    groups
  end

  defp block_groups(stmts) do
    stmts
    |> filter_def_nodes()
    |> Enum.chunk_by(fn {name, arity, _, _, _} -> {name, arity} end)
    |> Enum.flat_map(fn group ->
      case find_unreachable_in_group(group) do
        {_catchall, []} ->
          []

        {catchall, unreachable} ->
          if Enum.all?(unreachable, fn {_, _, _, _, node} -> catch_all?(node) end),
            do: [{catchall, unreachable}],
            else: []
      end
    end)
  end

  # Delete one merged range from END of catch-all through END of last redundant
  # catch-all clause.
  defp delete_patch({catchall, unreachable}) do
    catchall_end = catchall |> elem(4) |> Sourceror.get_range() |> Map.get(:end)
    last_end = unreachable |> List.last() |> elem(4) |> Sourceror.get_range() |> Map.get(:end)
    %{range: %{start: catchall_end, end: last_end}, change: ""}
  end

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

      # The clause name must be a statically-known atom. A dynamic head name
      # (`def unquote(op)(a, b)` inside a macro) cannot be identified, so distinct
      # macro-generated functions would otherwise collapse to one `{nil, arity}`
      # group and be deleted as "duplicates". We cannot prove reachability across
      # such clauses, so they are never catch-alls.
      {name, _, args} when is_atom(name) and is_list(args) ->
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
