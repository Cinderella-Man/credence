defmodule Credence.Pattern.PreferTupleForRandomAccess do
  @moduledoc """
  Detects `Enum.fetch!/2` on a list variable inside a `for` comprehension.

  Elixir lists are singly-linked, so `Enum.fetch!(list, i)` traverses the
  list from the head to reach element `i` — O(i) per call. When used inside
  a `for` comprehension (or any loop), repeated index accesses multiply the
  cost unnecessarily.

  Converting the list to a tuple with `List.to_tuple/1` and using `elem/2`
  gives O(1) random access, a significant performance improvement.

  ## Bad

      n = length(numbers)
      pairs = for i <- 0..(n - 2),
                  j <- (i + 1)..(n - 1),
                  abs(Enum.fetch!(numbers, i) - Enum.fetch!(numbers, j)) == k,
                  do: {i, j}

  ## Good

      tuple = List.to_tuple(numbers)
      n = tuple_size(tuple)
      pairs = for i <- 0..(n - 2),
                  j <- (i + 1)..(n - 1),
                  abs(elem(tuple, i) - elem(tuple, j)) == k,
                  do: {i, j}
  """
  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:for, meta, args} = node, issues when is_list(args) ->
          list_vars = find_list_vars_in_for(args)

          if list_vars != [] do
            issue = %Issue{
              rule: :prefer_tuple_for_random_access,
              message:
                "`Enum.fetch!/2` is used for random access inside a `for` " <>
                  "comprehension. Convert the list to a tuple with " <>
                  "`List.to_tuple/1` and use `elem/2` for O(1) access.",
              meta: %{line: Keyword.get(meta, :line)}
            }

            {node, [issue | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)
    RuleHelpers.patches_from_ast_transform(ast, source, &transform_ast/1)
  end

  # -- AST transformation --

  defp transform_ast(ast) do
    # Phase 1: collect all list vars from Enum.fetch! inside for comprehensions
    all_list_vars = collect_all_for_fetch_list_vars(ast)

    if all_list_vars == [] do
      ast
    else
      # Phase 2: build the list_var → tuple_var mapping
      var_map =
        Map.new(all_list_vars, fn lv ->
          {lv, String.to_atom("#{lv}_tuple")}
        end)

      # Phase 3: rewrite Enum.fetch! → elem and length → tuple_size
      rewritten =
        Macro.postwalk(ast, fn
          # Enum.fetch!(list, idx) → elem(tuple, idx)
          {{:., _, [{:__aliases__, _, [:Enum]}, :fetch!]}, _meta, [list_arg, idx]} = node ->
            case list_arg do
              {name, _, ctx} when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) ->
                case Map.get(var_map, name) do
                  nil -> node
                  tv -> {:elem, [], [{tv, [], nil}, idx]}
                end

              _ ->
                node
            end

          # length(list) → tuple_size(tuple)
          {:length, _meta, [arg]} = node ->
            case arg do
              {name, _, ctx} when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) ->
                case Map.get(var_map, name) do
                  nil -> node
                  tv -> {:tuple_size, [], [{tv, [], nil}]}
                end

              _ ->
                node
            end

          node ->
            node
        end)

      # Phase 4: insert tuple conversions at the start of blocks that have
      # statements with for comprehensions.
      #
      # NOTE: Macro.postwalk processes children before parents. This means
      # a `for` expression inside `pairs = for ...` has already been rewritten
      # (Enum.fetch! → elem) by the time we see the parent block. We only
      # insert at the block level — standalone `for` expressions outside any
      # block are handled separately in transform_ast's top-level postwalk.
      rewritten
      |> Macro.postwalk(fn
        {:__block__, _meta, stmts} = node when is_list(stmts) ->
          insert_tuple_conversions(node, stmts, var_map)

        node ->
          node
      end)
      |> handle_standalone_for(var_map)
      |> strip_all_layout_meta()
    end
  end

  # Insert tuple conversions at the start of a block if it has any statement
  # with a `for` comprehension.
  defp insert_tuple_conversions(node, stmts, var_map) do
    has_for? =
      Enum.any?(stmts, fn stmt ->
        stmt_has_for?(stmt)
      end)

    if has_for? do
      tuple_stmts = build_tuple_assignments(var_map)
      {:__block__, [], tuple_stmts ++ stmts}
    else
      node
    end
  end

  # Handle standalone `for` expressions (top-level, not inside any block).
  # These need tuple conversions prepended since there's no parent block
  # to insert into.
  # NOTE: Enum.fetch! has already been rewritten to elem in Phase 3,
  # so we check for elem calls on our known tuple variables instead.
  defp handle_standalone_for({:for, _meta, args} = node, var_map) when is_list(args) do
    tuple_vars = Map.values(var_map) |> MapSet.new()

    if for_has_elem_on_tuple?(args, tuple_vars) do
      tuple_stmts = build_tuple_assignments(var_map)
      {:__block__, [], tuple_stmts ++ [node]}
    else
      node
    end
  end

  defp handle_standalone_for(ast, _var_map), do: ast

  defp for_has_elem_on_tuple?(args, tuple_vars) do
    {_args, found} =
      Macro.prewalk(args, false, fn
        {:elem, _, [{tv, _, nil}, _idx]}, _acc when is_atom(tv) ->
          {nil, MapSet.member?(tuple_vars, tv)}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # -- Detection helpers --

  defp collect_all_for_fetch_list_vars(ast) do
    {_ast, vars} =
      Macro.prewalk(ast, [], fn
        {:for, _meta, args} = node, acc when is_list(args) ->
          list_vars = find_list_vars_in_for(args)
          {node, list_vars ++ acc}

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(vars)
  end

  defp stmt_has_for?({:=, _, [_lhs, {:for, _, args}]}) when is_list(args), do: true
  defp stmt_has_for?({:for, _, args}) when is_list(args), do: true
  defp stmt_has_for?(_), do: false

  defp find_list_vars_in_for(args) do
    {_args, vars} =
      Macro.prewalk(args, [], fn
        {{:., _, [{:__aliases__, _, [:Enum]}, :fetch!]}, _, [list_arg, _idx]} = node, acc ->
          case list_arg do
            {name, _, ctx} when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) ->
              {node, [name | acc]}

            _ ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(vars)
  end

  # -- AST builders --

  defp build_tuple_assignments(var_map) do
    Enum.map(var_map, fn {lv, tv} ->
      build_tuple_assignment(lv, tv)
    end)
  end

  defp build_tuple_assignment(list_var, tuple_var) do
    {:=, [],
     [
       {tuple_var, [], nil},
       {{:., [], [{:__aliases__, [], [:List]}, :to_tuple]}, [],
        [{list_var, [], nil}]}
     ]}
  end

  # Strip layout metadata from all nodes so Sourceror makes fresh formatting
  # decisions based on line length rather than original source positions.
  defp strip_all_layout_meta(ast) do
    Macro.prewalk(ast, fn
      {form, meta, args} when is_list(meta) ->
        {form,
         Keyword.drop(meta, [
           :line,
           :column,
           :closing,
           :last,
           :end,
           :end_of_expression,
           :parens,
           :token,
           :indentation,
           :format,
           :trailing_comments,
           :leading_comments
         ]), args}

      node ->
        node
    end)
  end
end
