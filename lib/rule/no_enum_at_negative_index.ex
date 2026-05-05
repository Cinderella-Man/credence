defmodule Credence.Rule.NoEnumAtNegativeIndex do
  @moduledoc """
  Detects `Enum.at/2` called with a negative integer literal index.

  Elixir lists are singly-linked, so `Enum.at(list, -1)` traverses the
  entire list to reach the last element. Calling `Enum.at(list, -2)` does
  the same to reach the second-to-last, and so on — each call pays O(n).

  When multiple negative-index accesses target the same list, the
  cost multiplies unnecessarily.

  ## Bad

      last = Enum.at(sorted_list, -1)
      one_before_last = Enum.at(sorted_list, -2)

      value = sorted |> Enum.at(-1)

  ## Good

      # For multiple tail elements, reverse once and pattern-match
      sorted_list_reversed = Enum.reverse(sorted_list)
      [last, one_before_last | _] = sorted_list_reversed

      # For a single last element, use List.last/1
      value = List.last(sorted)

  ## Auto-fix

  When multiple assignments access the same list variable with negative
  indices within the same function, the fixer groups them into a single
  `Enum.reverse/1` call and a pattern match (up to depth 5).

  A lone `Enum.at(x, -1)` is rewritten to `List.last(x)`.

  A lone `Enum.at(x, -N)` where N > 1 is rewritten to a reverse +
  pattern match on a single variable.
  """

  use Credence.Rule
  alias Credence.Issue

  @max_fixable_depth 5

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Direct call: Enum.at(list, <neg>)
        {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, meta, [_list, idx_node]} = node, issues ->
          case extract_negative_index(idx_node) do
            {:ok, index} -> {node, [build_issue(meta, index) | issues]}
            :error -> {node, issues}
          end

        # Pipe: ... |> Enum.at(<neg>)
        {:|>, _, [_lhs, {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, meta, [idx_node]}]} = node,
        issues ->
          case extract_negative_index(idx_node) do
            {:ok, index} -> {node, [build_issue(meta, index) | issues]}
            :error -> {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    ast = Sourceror.parse_string!(source)
    lines = String.split(source, "\n")

    # Step 1: Collect assignment-form Enum.at(var, -N) entries, scoped by function
    entries = collect_assignment_entries(ast)

    # Step 2: Keep only entries whose source line matches a single-line pattern
    entries = Enum.filter(entries, &single_line_match?(&1, lines))

    # Step 3: Group by {scope, list_var}
    groups =
      entries
      |> Enum.group_by(fn e -> {e.scope, e.list_var} end)
      |> Map.values()

    # Step 4: Separate into reverse-groups (multi or non-(-1)) and simple-last
    {reverse_groups, last_groups} =
      Enum.split_with(groups, fn grp ->
        length(grp) >= 2 or Enum.any?(grp, &(&1.index != -1))
      end)

    # Step 5: Validate reverse groups (unique lhs vars, indices in range)
    reverse_groups = Enum.filter(reverse_groups, &valid_reverse_group?/1)

    # Step 6: Build line-level action map
    actions = build_all_actions(reverse_groups, last_groups, lines)

    # Step 7: Apply actions to produce modified source
    result =
      lines
      |> apply_actions(actions)
      |> Enum.join("\n")

    # Step 8: Fix remaining non-assignment Enum.at(x, -1) via targeted line regex
    fix_remaining_minus_one(result)
  end

  # ── Negative index extraction ──────────────────────────────────────
  #
  # Elixir AST represents `-1` as `{:-, meta, [1]}` (unary minus).
  # Sourceror additionally wraps the inner literal:
  #   `{:-, meta, [{:__block__, meta, [1]}]}`
  # We handle all representations.

  defp extract_negative_index({:-, _, [{:__block__, _, [n]}]}) when is_integer(n) and n > 0,
    do: {:ok, -n}

  defp extract_negative_index({:-, _, [n]}) when is_integer(n) and n > 0, do: {:ok, -n}
  defp extract_negative_index({:__block__, _, [n]}), do: extract_negative_index(n)
  defp extract_negative_index(n) when is_integer(n) and n < 0, do: {:ok, n}
  defp extract_negative_index(_), do: :error

  # ── Entry collection ───────────────────────────────────────────────

  defp collect_assignment_entries(ast) do
    {_ast, {entries, _scope}} =
      Macro.traverse(ast, {[], nil}, &pre_collect/2, &post_collect/2)

    Enum.reverse(entries)
  end

  # Track function scope (enter)
  defp pre_collect({def_type, meta, _} = node, {entries, _scope})
       when def_type in [:def, :defp] do
    {node, {entries, Keyword.get(meta, :line)}}
  end

  # var = Enum.at(list_var, -N)
  defp pre_collect(
         {:=, meta,
          [
            {lhs, _, lhs_ctx},
            {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [{list_var, _, list_ctx}, idx_node]}
          ]} = node,
         {entries, scope}
       )
       when is_atom(lhs) and is_atom(list_var) and
              scope != nil and
              (is_nil(lhs_ctx) or is_atom(lhs_ctx)) and
              (is_nil(list_ctx) or is_atom(list_ctx)) do
    case extract_negative_index(idx_node) do
      {:ok, idx} when idx >= -@max_fixable_depth ->
        entry = %{
          lhs_var: lhs,
          list_var: list_var,
          index: idx,
          line: Keyword.get(meta, :line),
          scope: scope
        }

        {node, {[entry | entries], scope}}

      _ ->
        {node, {entries, scope}}
    end
  end

  # var = list_var |> Enum.at(-N)
  defp pre_collect(
         {:=, meta,
          [
            {lhs, _, lhs_ctx},
            {:|>, _,
             [
               {list_var, _, list_ctx},
               {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [idx_node]}
             ]}
          ]} = node,
         {entries, scope}
       )
       when is_atom(lhs) and is_atom(list_var) and
              scope != nil and
              (is_nil(lhs_ctx) or is_atom(lhs_ctx)) and
              (is_nil(list_ctx) or is_atom(list_ctx)) do
    case extract_negative_index(idx_node) do
      {:ok, idx} when idx >= -@max_fixable_depth ->
        entry = %{
          lhs_var: lhs,
          list_var: list_var,
          index: idx,
          line: Keyword.get(meta, :line),
          scope: scope
        }

        {node, {[entry | entries], scope}}

      _ ->
        {node, {entries, scope}}
    end
  end

  defp pre_collect(node, acc), do: {node, acc}

  # Track function scope (leave)
  defp post_collect({def_type, _, _} = node, {entries, _scope})
       when def_type in [:def, :defp] do
    {node, {entries, nil}}
  end

  defp post_collect(node, acc), do: {node, acc}

  # ── Verification ───────────────────────────────────────────────────

  # Confirm the source line is a single-line assignment we can safely edit
  defp single_line_match?(entry, lines) do
    line_idx = entry.line - 1

    if line_idx >= 0 and line_idx < length(lines) do
      line = Enum.at(lines, line_idx)

      Regex.match?(
        ~r/^\s*\w+\s*=\s*(Enum\.at\(\w+,\s*-\d+\)|\w+\s*\|>\s*Enum\.at\(-\d+\))\s*$/,
        line
      )
    else
      false
    end
  end

  # Ensure the group has unique LHS variable names (otherwise pattern match fails)
  defp valid_reverse_group?(entries) do
    lhs_vars = Enum.map(entries, & &1.lhs_var)
    length(lhs_vars) == length(Enum.uniq(lhs_vars))
  end

  # ── Action building ────────────────────────────────────────────────

  defp build_all_actions(reverse_groups, last_groups, lines) do
    actions =
      Enum.reduce(reverse_groups, %{}, fn entries, acc ->
        build_reverse_actions(entries, lines, acc)
      end)

    Enum.reduce(last_groups, actions, fn
      [entry], acc -> build_list_last_action(entry, lines, acc)
      _, acc -> acc
    end)
  end

  defp build_reverse_actions(entries, lines, actions) do
    sorted = Enum.sort_by(entries, &abs(&1.index))
    first_entry = Enum.min_by(entries, & &1.line)
    other_entries = Enum.reject(entries, &(&1.line == first_entry.line))

    first_line_idx = first_entry.line - 1
    first_line = Enum.at(lines, first_line_idx)
    indent = extract_indent(first_line)

    list_var = Atom.to_string(first_entry.list_var)
    reversed_var = "#{list_var}_reversed"

    # Build pattern elements, filling gaps with _
    max_depth = abs(List.last(sorted).index)

    elements =
      for pos <- 1..max_depth do
        case Enum.find(sorted, &(abs(&1.index) == pos)) do
          nil -> "_"
          entry -> Atom.to_string(entry.lhs_var)
        end
      end

    pattern = "[#{Enum.join(elements, ", ")} | _]"

    replacement = [
      "#{indent}#{reversed_var} = Enum.reverse(#{list_var})",
      "#{indent}#{pattern} = #{reversed_var}"
    ]

    actions = Map.put(actions, first_line_idx, {:replace, replacement})

    Enum.reduce(other_entries, actions, fn entry, acc ->
      Map.put(acc, entry.line - 1, :delete)
    end)
  end

  defp build_list_last_action(entry, lines, actions) do
    line_idx = entry.line - 1
    line = Enum.at(lines, line_idx)
    indent = extract_indent(line)

    lhs = Atom.to_string(entry.lhs_var)
    list = Atom.to_string(entry.list_var)

    replacement = ["#{indent}#{lhs} = List.last(#{list})"]
    Map.put(actions, line_idx, {:replace, replacement})
  end

  # ── Action application ─────────────────────────────────────────────

  defp apply_actions(lines, actions) when map_size(actions) == 0, do: lines

  defp apply_actions(lines, actions) do
    lines
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, idx} ->
      case Map.get(actions, idx) do
        {:replace, new_lines} -> new_lines
        :delete -> []
        nil -> [line]
      end
    end)
  end

  # ── Remaining inline -1 fix ────────────────────────────────────────

  # Handle non-assignment Enum.at(x, -1) calls that weren't caught above
  defp fix_remaining_minus_one(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        remaining_lines = find_minus_one_lines(ast)

        if remaining_lines == [] do
          source
        else
          line_set = MapSet.new(remaining_lines)

          source
          |> String.split("\n")
          |> Enum.with_index(1)
          |> Enum.map(fn {line, idx} ->
            if idx in line_set, do: fix_minus_one_in_line(line), else: line
          end)
          |> Enum.join("\n")
        end

      {:error, _} ->
        source
    end
  end

  defp find_minus_one_lines(ast) do
    {_ast, lines} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, meta, [_, idx_node]} = node, acc ->
          case extract_negative_index(idx_node) do
            {:ok, -1} -> {node, [Keyword.get(meta, :line) | acc]}
            _ -> {node, acc}
          end

        {:|>, _, [_, {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, meta, [idx_node]}]} = node,
        acc ->
          case extract_negative_index(idx_node) do
            {:ok, -1} -> {node, [Keyword.get(meta, :line) | acc]}
            _ -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(lines)
  end

  defp fix_minus_one_in_line(line) do
    line
    |> then(&Regex.replace(~r/\|>\s*Enum\.at\(\s*-1\s*\)/, &1, "|> List.last()"))
    |> then(&Regex.replace(~r/Enum\.at\((\w+),\s*-1\)/, &1, "List.last(\\1)"))
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp extract_indent(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, indent] -> indent
      _ -> ""
    end
  end

  defp build_issue(meta, index) do
    message =
      if index == -1 do
        """
        `Enum.at(list, -1)` traverses the entire list to reach the last element.

        Use `List.last/1` instead — it is semantically clearer and avoids the
        overhead of the generic `Enum.at/2` negative-index handling.
        """
      else
        """
        `Enum.at(list, #{index})` traverses the entire list to reach the element \
        #{abs(index)} positions from the end.

        Consider reversing the list once and pattern-matching the elements you need:

            [last, second_to_last | _rest] = Enum.reverse(list)
        """
      end

    %Issue{
      rule: :no_enum_at_negative_index,
      message: message,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
