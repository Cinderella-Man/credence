defmodule Credence.Pattern.PreferPipeMapsetIntersection do
  @moduledoc """
  Detects a sequence of `MapSet.new/1` assignments followed by nested
  `MapSet.intersection/2` calls piped into `MapSet.to_list/0`, and rewrites
  them into a single pipeline using `|>`.

  ## Bad

      set_a = MapSet.new(a)
      set_b = MapSet.new(b)
      set_c = MapSet.new(c)

      MapSet.intersection(set_a, MapSet.intersection(set_b, set_c))
      |> MapSet.to_list()

  ## Good

      a
      |> MapSet.new()
      |> MapSet.intersection(MapSet.new(b))
      |> MapSet.intersection(MapSet.new(c))
      |> MapSet.to_list()
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case check_node(node) do
          {:ok, issue} -> {node, [issue | acc]}
          :error -> {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)

    RuleHelpers.patches_from_ast_transform(ast, source, fn input ->
      Macro.postwalk(input, fn
        {:__block__, meta, exprs} when is_list(exprs) ->
          case transform_block(exprs) do
            {:ok, new_exprs} -> {:__block__, meta, new_exprs}
            :error -> {:__block__, meta, exprs}
          end

        node ->
          node
      end)
    end)
  end

  # ── detection helpers ──────────────────────────────────────────────

  defp check_node({:__block__, _meta, exprs}) when is_list(exprs) do
    case match_mapset_intersection_block(exprs) do
      {:ok, _sets, _final_expr} ->
        line = get_block_line(exprs)
        {:ok, build_issue(line)}

      :error ->
        :error
    end
  end

  defp check_node(_), do: :error

  defp get_block_line(exprs) do
    case exprs do
      [{:=, meta, _} | _] -> Keyword.get(meta, :line)
      _ -> nil
    end
  end

  defp build_issue(line) do
    %Issue{
      rule: :prefer_pipe_mapset_intersection,
      message:
        "Use a pipeline with `MapSet.intersection/2` instead of intermediate " <>
          "`MapSet.new/1` variables and nested `MapSet.intersection/2` calls.",
      meta: %{line: line}
    }
  end

  # Match a block with MapSet.new assignments followed by a MapSet.intersection pipeline.
  # Returns {:ok, [{var, expr}, ...], final_expr} or :error.
  defp match_mapset_intersection_block(exprs) do
    {assignments, rest} = collect_mapset_assignments(exprs)

    case assignments do
      [_ | _] ->
        case rest do
          [final_expr] ->
            vars = Enum.map(assignments, fn {v, _} -> v end)

            case extract_intersection_chain(final_expr, vars) do
              {:ok, ordered_vars} ->
                # Only safe when the chain consumes each assignment exactly once,
                # in the same order they were written. Equal order keeps the arg
                # evaluation order identical and guarantees the whole block is
                # replaced (no dangling assignment, no var evaluated twice). A
                # reordered or duplicated chain would diverge on side-effecting
                # args or leave dead code, so we leave it alone.
                if vars == Enum.uniq(vars) and ordered_vars == vars do
                  {:ok, build_sets(ordered_vars, assignments), final_expr}
                else
                  :error
                end

              :error ->
                :error
            end

          _ ->
            :error
        end

      [] ->
        :error
    end
  end

  # Pair each ordered var back to its MapSet.new assignment expression.
  defp build_sets(ordered_vars, assignments) do
    for v <- ordered_vars do
      {_, expr} = Enum.find(assignments, fn {av, _} -> av == v end)
      {v, expr}
    end
  end

  # Collect consecutive MapSet.new assignments from the start of a list.
  defp collect_mapset_assignments(exprs) do
    do_collect(exprs, [])
  end

  defp do_collect(
         [{:=, _meta, [{var, _, nil}, mapset_call]} | rest] = all,
         acc
       ) do
    if mapset_new_call?(mapset_call) do
      do_collect(rest, acc ++ [{var, mapset_call}])
    else
      {acc, all}
    end
  end

  defp do_collect(rest, acc), do: {acc, rest}

  # Check if an expression is a MapSet.new/1 call.
  defp mapset_new_call?({{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, _, [_]}), do: true
  defp mapset_new_call?(_), do: false

  # Extract the ordered list of variables from a nested MapSet.intersection chain.
  # The expression must be a MapSet.to_list(MapSet.intersection(set_a, MapSet.intersection(set_b, set_c)))
  # or piped variant. Returns {:ok, ordered_vars} where the first var is the outermost.
  defp extract_intersection_chain(expr, all_vars) do
    case expr do
      # MapSet.to_list(MapSet.intersection(a, MapSet.intersection(b, c)))
      {{:., _, [{:__aliases__, _, [:MapSet]}, :to_list]}, _, [inner]} ->
        extract_intersection_vars(inner, all_vars)

      # MapSet.intersection(a, MapSet.intersection(b, c)) |> MapSet.to_list()
      {:|>, _pipe_meta,
       [
         inner,
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [:MapSet]}, :to_list]}, _call_meta, []}
       ]} ->
        extract_intersection_vars(inner, all_vars)

      _ ->
        :error
    end
  end

  defp extract_intersection_vars(node, all_vars) do
    case node do
      # Base case: MapSet.intersection(set_b, set_c)
      {{:., _dot_meta, [{:__aliases__, _alias_meta, [:MapSet]}, :intersection]}, _call_meta,
       [{var_a, _, nil}, {var_b, _, nil}]}
      when is_atom(var_a) and is_atom(var_b) ->
        if var_a in all_vars and var_b in all_vars do
          {:ok, [var_a, var_b]}
        else
          :error
        end

      # Recursive case: MapSet.intersection(var, nested_intersection)
      {{:., _dot_meta, [{:__aliases__, _alias_meta, [:MapSet]}, :intersection]}, _call_meta,
       [{var_a, _, nil}, inner]}
      when is_atom(var_a) ->
        if var_a in all_vars do
          case extract_intersection_vars(inner, all_vars) do
            {:ok, rest_vars} -> {:ok, [var_a | rest_vars]}
            :error -> :error
          end
        else
          :error
        end

      _ ->
        :error
    end
  end

  # ── block transformation ──────────────────────────────────────────

  defp transform_block(exprs) do
    case match_mapset_intersection_block(exprs) do
      {:ok, sets, _final_expr} ->
        build_transformed_block(sets, exprs)

      :error ->
        :error
    end
  end

  defp build_transformed_block(sets, original_exprs) do
    [{_first_var, first_expr} | rest_sets] = sets
    {_, first_arg} = extract_mapset_new_arg(first_expr)

    # Start with the first argument piped into MapSet.new()
    base_pipe =
      pipe(first_arg, {{:., [], [{:__aliases__, [], [:MapSet]}, :new]}, [], []})

    # Chain each remaining set through MapSet.intersection
    pipeline =
      Enum.reduce(rest_sets, base_pipe, fn {_var, expr}, acc ->
        {_, arg} = extract_mapset_new_arg(expr)

        intersection_call =
          {{:., [], [{:__aliases__, [], [:MapSet]}, :intersection]}, [],
           [{{:., [], [{:__aliases__, [], [:MapSet]}, :new]}, [], [arg]}]}

        pipe(acc, intersection_call)
      end)

    # Add MapSet.to_list() at the end
    final_pipeline =
      pipe(pipeline, {{:., [], [{:__aliases__, [], [:MapSet]}, :to_list]}, [], []})

    # Replace the matched portion of the block
    # Find where the assignments start and the final expression ends
    {before, matched_count} = find_match_start(original_exprs, sets)
    remaining = Enum.drop(original_exprs, matched_count + 1)

    {:ok, before ++ [final_pipeline] ++ remaining}
  end

  # Extract the argument from a MapSet.new/1 call
  defp extract_mapset_new_arg({{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, _, [arg]}),
    do: {:ok, arg}

  # Find where the pattern starts in the expression list
  defp find_match_start(exprs, sets) do
    first_var = elem(hd(sets), 0)

    case Enum.find_index(exprs, fn
           {:=, _, [{^first_var, _, nil}, _]} -> true
           _ -> false
         end) do
      nil -> {exprs, 0}
      idx -> {Enum.take(exprs, idx), length(sets)}
    end
  end

  defp pipe(left, right), do: {:|>, [], [left, right]}
end
