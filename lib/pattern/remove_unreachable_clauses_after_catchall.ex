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
  def fix_patches(ast, opts) do
    source = Keyword.get(opts, :source) || Sourceror.to_string(ast)

    Credence.RuleHelpers.patches_from_ast_transform(ast, source, fn ast ->
      Macro.prewalk(ast, fn
        {:__block__, meta, stmts} when is_list(stmts) ->
          {:__block__, meta, remove_unreachable_from_block(stmts)}

        node ->
          node
      end)
    end)
  end

  # Given a list of statements in a block, find consecutive def/defp groups
  # and remove unreachable clauses.
  defp remove_unreachable_from_block(stmts) do
    # Build a set of unreachable nodes to remove
    unreachable =
      stmts
      |> filter_def_nodes()
      |> Enum.chunk_by(fn {name, arity, _, _, _} -> {name, arity} end)
      |> Enum.flat_map(fn group ->
        case find_unreachable_in_group(group) do
          {_, []} -> []
          {_catchall, unreachable} -> Enum.map(unreachable, &elem(&1, 4))
        end
      end)
      |> MapSet.new()

    Enum.reject(stmts, &MapSet.member?(unreachable, &1))
  end

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
  defp filter_def_nodes(stmts) do
    Enum.flat_map(stmts, fn
      {dt, meta, [head | _]} = node when dt in [:def, :defp] ->
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
  # and no guard.
  defp catch_all?({dt, _, [head | _]}) when dt in [:def, :defp] do
    case head do
      {:when, _, _} ->
        false

      {_, _, args} when is_list(args) ->
        args != [] and Enum.all?(args, &bare_var_or_underscore?/1)

      _ ->
        false
    end
  end

  defp catch_all?(_), do: false

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
