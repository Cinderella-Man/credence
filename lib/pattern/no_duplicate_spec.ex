defmodule Credence.Pattern.NoDuplicateSpec do
  @moduledoc """
  Detects duplicate `@spec` annotations before function clauses.

  In Elixir, `@spec` is a compile-time type annotation consumed by tools like
  Dialyzer — it has zero runtime effect. Writing the same `@spec` before every
  clause of a function is redundant noise: the compiler only needs one. This
  rule flags the duplicates and removes them, keeping the first `@spec` per
  function name.

  ## Bad

      @spec largest_square_number(non_neg_integer()) :: non_neg_integer()
      def largest_square_number(0), do: 0

      @spec largest_square_number(non_neg_integer()) :: non_neg_integer()
      def largest_square_number(number) when is_integer(number) and number >= 0 do
        root = floor(:math.sqrt(number))
        root * root
      end

  ## Good

      @spec largest_square_number(non_neg_integer()) :: non_neg_integer()
      def largest_square_number(0), do: 0

      def largest_square_number(number) when is_integer(number) and number >= 0 do
        root = floor(:math.sqrt(number))
        root * root
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
          new_issues = detect_duplicate_specs(stmts) ++ acc
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
          {:__block__, meta, strip_duplicate_specs(stmts)}

        node ->
          node
      end)
    end)
  end

  # Indices of @spec statements in `stmts` that are redundant duplicates. A spec
  # is keyed on BOTH its text AND the function it annotates — the {name, arity}
  # of the first def/defp that follows it. Keying on text alone wrongly deleted
  # textually-identical specs that annotate *different* functions (e.g. a
  # correctly-placed `@spec start_link/0` deleted as a "dup" of a misplaced one
  # before `start_link/1`, or a `@spec test_project` above `def phx_test_project`).
  defp duplicate_spec_indices(stmts) do
    {_seen, dups} =
      stmts
      |> Enum.with_index()
      |> Enum.reduce({MapSet.new(), MapSet.new()}, fn {stmt, idx}, {seen, dups} ->
        case spec_dedup_key(stmt, stmts, idx) do
          nil ->
            {seen, dups}

          key ->
            if MapSet.member?(seen, key),
              do: {seen, MapSet.put(dups, idx)},
              else: {MapSet.put(seen, key), dups}
        end
      end)

    dups
  end

  defp detect_duplicate_specs(stmts) do
    dups = duplicate_spec_indices(stmts)

    for {stmt, idx} <- Enum.with_index(stmts), MapSet.member?(dups, idx), do: build_issue(stmt)
  end

  defp strip_duplicate_specs(stmts) do
    dups = duplicate_spec_indices(stmts)

    stmts
    |> Enum.with_index()
    |> Enum.reject(fn {_stmt, idx} -> MapSet.member?(dups, idx) end)
    |> Enum.map(&elem(&1, 0))
  end

  # Dedup key for a @spec: {full text (name, arity, AND types), annotated
  # function {name, arity}}. `nil` when the statement is not a spec, or no
  # function follows it (then it annotates nothing and is never a duplicate).
  defp spec_dedup_key({:@, _, [{:spec, _, [spec_expr]}]}, stmts, idx) do
    case following_def_name_arity(stmts, idx) do
      nil -> nil
      name_arity -> {Macro.to_string(spec_expr), name_arity}
    end
  end

  defp spec_dedup_key(_, _, _), do: nil

  # {name, arity} of the first def/defp that follows the statement at `idx` (the
  # function this @spec is positioned to annotate), or nil.
  defp following_def_name_arity(stmts, idx) do
    stmts
    |> Enum.drop(idx + 1)
    |> Enum.find_value(fn
      {dt, _, [head | _]} when dt in [:def, :defp, :defmacro, :defmacrop] -> def_name_arity(head)
      _ -> nil
    end)
  end

  defp def_name_arity({:when, _, [inner | _]}), do: def_name_arity(inner)

  defp def_name_arity({name, _, args}) when is_atom(name) and is_list(args),
    do: {name, length(args)}

  defp def_name_arity({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: {name, 0}
  defp def_name_arity(_), do: nil

  # {name, arity} of a @spec, for the issue message.
  defp spec_name_arity({:@, _, [{:spec, _, [spec_expr]}]}), do: fun_name_arity(spec_expr)
  defp spec_name_arity(_), do: {:unknown, 0}

  defp fun_name_arity({:when, _, [spec_expr, _constraints]}), do: fun_name_arity(spec_expr)

  defp fun_name_arity({:"::", _, [{name, _, args} | _]}) when is_atom(name),
    do: {name, arity(args)}

  defp fun_name_arity(_), do: {:unknown, 0}

  defp arity(args) when is_list(args), do: length(args)
  defp arity(_), do: 0

  defp build_issue(node) do
    {name, arity} = spec_name_arity(node)
    meta = elem(node, 1)

    %Issue{
      rule: :no_duplicate_spec,
      message:
        "Duplicate `@spec` for `#{name}/#{arity}`. " <>
          "`@spec` is a compile-time annotation; the second one is redundant and should be removed.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
