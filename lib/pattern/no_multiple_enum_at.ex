defmodule Credence.Pattern.NoMultipleEnumAt do
  @moduledoc """
  Readability & performance rule: Detects multiple `Enum.at/2` calls on the
  same variable with literal indices. Each `Enum.at/2` traverses the list
  from the head, so N calls cost O(N × len). Pattern matching destructures
  the list in a single pass.

  The rule fires when 3 or more `Enum.at(var, literal)` calls target the
  same variable, since that is a strong signal the code should use pattern
  matching instead.

  ## Bad

      sorted = Enum.sort(nums)
      min1 = Enum.at(sorted, 0)
      min2 = Enum.at(sorted, 1)
      max1 = Enum.at(sorted, -1)
      max2 = Enum.at(sorted, -2)

  ## Good

      sorted = Enum.sort(nums)
      [min1, min2 | _] = sorted
      [max1, max2 | _] = Enum.reverse(sorted)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @min_calls_to_flag 3
  # Only build a destructuring pattern when the total list positions spanned
  # is at most `@max_gap_ratio × number_of_bindings`.  Prevents absurdly
  # long patterns like `[a, _, _, _, _, _, _, b | _]`.
  @max_gap_ratio 2

  @impl true
  def check(ast, _opts) do
    {_ast, calls} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, meta, [{var_name, _, nil}, idx]} = node, acc
        when is_atom(var_name) ->
          if literal_index?(idx) do
            {node, [{var_name, Keyword.get(meta, :line)} | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    calls
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.flat_map(fn {var_name, entries} ->
      if length(entries) >= @min_calls_to_flag do
        first_line = entries |> Enum.map(&elem(&1, 1)) |> Enum.min()

        [
          %Issue{
            rule: :no_multiple_enum_at,
            message:
              "`Enum.at/2` is called #{length(entries)} times on `#{var_name}`. " <>
                "Each call traverses the list from the head. Use pattern matching " <>
                "(e.g. `[a, b | _] = #{var_name}`) to destructure in a single pass.",
            meta: %{line: first_line}
          }
        ]
      else
        []
      end
    end)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)

    RuleHelpers.patches_from_ast_transform(ast, source, fn input ->
      {new_ast, _changed?} = apply_fixes(input)
      new_ast
    end)
  end

  # Walks the Sourceror AST looking for real multi-statement `:__block__`
  # nodes (single-child blocks are Sourceror literal wrappers and are
  # skipped). When a block contains bare `var = Enum.at(...)` assignments
  # on the same source variable, replace them with a destructure pattern.
  defp apply_fixes(ast) do
    Macro.prewalk(ast, false, fn
      {:__block__, meta, children}, changed?
      when is_list(children) and length(children) >= 2 ->
        case fix_block(children) do
          {:changed, new_children} ->
            {{:__block__, meta, new_children}, true}

          :unchanged ->
            {{:__block__, meta, children}, changed?}
        end

      node, changed? ->
        {node, changed?}
    end)
  end

  defp fix_block(children) do
    groups = find_contiguous_enum_at_groups(children)
    fixes = compute_fixes(groups)

    case fixes do
      [] -> :unchanged
      _ -> {:changed, insert_fixes(children, fixes)}
    end
  end

  defp find_contiguous_enum_at_groups(children) do
    {groups, current} =
      Enum.reduce(children, {[], []}, fn child, {groups, current} ->
        case extract_enum_at_info(child) do
          {:ok, info} ->
            {groups, [info | current]}

          :error ->
            g = if current != [], do: [Enum.reverse(current) | groups], else: groups
            {g, []}
        end
      end)

    groups = if current != [], do: [Enum.reverse(current) | groups], else: groups
    Enum.reverse(groups)
  end

  defp extract_enum_at_info(
         {:=, _,
          [
            {target, _, nil},
            {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [{source, _, nil}, idx]}
          ]} = node
       )
       when is_atom(target) and is_atom(source) do
    case normalize_index(idx) do
      {:ok, norm} -> {:ok, {source, target, norm, node}}
      :error -> :error
    end
  end

  defp extract_enum_at_info(_), do: :error

  # Sourceror wraps integer literals in `{:__block__, _, [n]}`; negatives
  # are `{:-, _, [{:__block__, _, [n]}]}` — unary minus over a wrapped
  # positive.
  defp normalize_index({:__block__, _, [n]}) when is_integer(n), do: {:ok, n}
  defp normalize_index({:-, _, [{:__block__, _, [n]}]}) when is_integer(n), do: {:ok, -n}
  defp normalize_index(_), do: :error

  defp compute_fixes(groups) do
    Enum.flat_map(groups, fn group ->
      group
      |> Enum.group_by(&elem(&1, 0))
      |> Enum.flat_map(fn {source_var, entries} ->
        if length(entries) >= @min_calls_to_flag do
          case build_fix(entries, source_var) do
            {:ok, fix} -> [fix]
            :error -> []
          end
        else
          []
        end
      end)
    end)
  end

  defp build_fix(entries, source_var) do
    {non_neg, neg} = Enum.split_with(entries, fn {_, _, idx, _} -> idx >= 0 end)

    results =
      [
        maybe_build_pattern(non_neg, source_var, :positive),
        maybe_build_pattern(neg, source_var, :negative)
      ]
      |> Enum.reject(&is_nil/1)

    case results do
      [] ->
        :error

      _ ->
        nodes = Enum.flat_map(results, fn {ents, _} -> Enum.map(ents, &elem(&1, 3)) end)
        exprs = Enum.map(results, fn {_, expr} -> expr end)
        {:ok, {nodes, exprs}}
    end
  end

  defp maybe_build_pattern(entries, source_var, direction) do
    if length(entries) >= 2 do
      case build_pattern_expr(entries, source_var, direction) do
        nil -> nil
        expr -> {entries, expr}
      end
    end
  end

  defp build_pattern_expr(entries, source_var, direction) do
    sorted =
      case direction do
        :positive -> Enum.sort_by(entries, &elem(&1, 2))
        :negative -> Enum.sort_by(entries, &elem(&1, 2), :desc)
      end

    indices = Enum.map(sorted, &elem(&1, 2))
    targets = Enum.map(sorted, &elem(&1, 1))

    non_wild =
      Enum.reject(targets, fn t ->
        String.starts_with?(Atom.to_string(t), "_")
      end)

    cond do
      length(indices) != length(Enum.uniq(indices)) ->
        nil

      length(non_wild) != length(Enum.uniq(non_wild)) ->
        nil

      true ->
        {min_idx, max_idx} = Enum.min_max(indices)

        range_size =
          case direction do
            :positive -> max_idx + 1
            :negative -> abs(min_idx)
          end

        if range_size > length(indices) * @max_gap_ratio do
          nil
        else
          build_pattern_ast(sorted, min_idx, max_idx, source_var, direction)
        end
    end
  end

  defp build_pattern_ast(sorted, min_idx, max_idx, source_var, direction) do
    index_to_var = Map.new(sorted, fn {_, target, idx, _} -> {idx, target} end)

    range =
      case direction do
        :positive -> 0..max_idx
        :negative -> -1..min_idx//-1
      end

    elements =
      Enum.map(range, fn i ->
        case Map.get(index_to_var, i) do
          nil -> "_"
          var -> Atom.to_string(var)
        end
      end)

    rhs =
      case direction do
        :positive -> Atom.to_string(source_var)
        :negative -> "Enum.reverse(#{Atom.to_string(source_var)})"
      end

    code = "[#{Enum.join(elements, ", ")} | _] = #{rhs}"
    Sourceror.parse_string!(code)
  end

  defp insert_fixes(children, fixes) do
    child_index = Map.new(Enum.with_index(children), fn {c, i} -> {c, i} end)

    node_role =
      Enum.reduce(fixes, %{}, fn {nodes, exprs}, acc ->
        first = Enum.min_by(nodes, &Map.get(child_index, &1))

        Enum.reduce(nodes, acc, fn node, a ->
          role = if node == first, do: {:insert, exprs}, else: :skip
          Map.put(a, node, role)
        end)
      end)

    Enum.flat_map(children, fn child ->
      case Map.get(node_role, child) do
        {:insert, exprs} -> exprs
        :skip -> []
        nil -> [child]
      end
    end)
  end

  defp literal_index?({:__block__, _, [n]}) when is_integer(n), do: true
  defp literal_index?({:-, _, [{:__block__, _, [n]}]}) when is_integer(n), do: true
  defp literal_index?(_), do: false
end
