defmodule Credence.Rule.NoManualEnumUniq do
  @moduledoc """
  Performance and idiomatic code rule: warns when `Enum.uniq/1` is manually
  reimplemented using `Enum.reduce/3` and `MapSet`.

  Lists are deduplicated most efficiently using the built-in `Enum.uniq/1`
  or `Enum.uniq_by/2`, which are implemented natively.

  ## Bad

      Enum.reduce(list, {MapSet.new(), []}, fn item, {seen, acc} ->
        if MapSet.member?(seen, item) do
          {seen, acc}
        else
          {MapSet.put(seen, item), [item | acc]}
        end
      end)

      # or in a pipeline:
      list
      |> Enum.reduce({MapSet.new(), []}, fn item, {seen, acc} ->
        if MapSet.member?(seen, item) do
          {seen, acc}
        else
          {MapSet.put(seen, item), [item | acc]}
        end
      end)

      # or with inverted tuple order:
      Enum.reduce(list, {[], MapSet.new()}, fn x, {results, tracked} ->
        unless MapSet.member?(tracked, x) do
          {[x | results], MapSet.put(tracked, x)}
        else
          {results, tracked}
        end
      end)

  ## Good

      Enum.uniq(list)
  """

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [_list, init_acc, fun]} = node,
        issues ->
          if manual_uniq?(init_acc, fun) do
            {node, [trigger_issue(meta) | issues]}
          else
            {node, issues}
          end

        {:|>, meta, [_, {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [init_acc, fun]}]} =
            node,
        issues ->
          if manual_uniq?(init_acc, fun) do
            {node, [trigger_issue(meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    {:ok, ast} = Code.string_to_quoted(source)

    fixes = collect_fixes(ast)

    fixes
    |> Enum.sort_by(fn {line, _kind, _list_str} -> line end, :desc)
    |> Enum.reduce(source, fn {line, kind, list_str}, src ->
      # Find byte offset of the target line in the full source
      line_offset = line_byte_offset(src, line)
      remaining = binary_part(src, line_offset, byte_size(src) - line_offset)

      case :binary.match(remaining, "Enum.reduce(") do
        {match_start, match_len} ->
          call_start = line_offset + match_start
          after_name = line_offset + match_start + match_len
          rest_from_paren = binary_part(src, after_name - 1, byte_size(src) - (after_name - 1))

          case find_matching_paren(rest_from_paren, 0, 0) do
            {:ok, paren_offset} ->
              call_end = after_name - 1 + paren_offset

              case kind do
                :direct ->
                  prefix = binary_part(src, 0, call_start)
                  suffix = binary_part(src, call_end, byte_size(src) - call_end)
                  prefix <> "Enum.uniq(#{list_str})" <> suffix

                _pipe ->
                  # For pipes (simple or complex), replace Enum.reduce(...)
                  # with Enum.uniq() — the list arrives via the pipe.
                  prefix = binary_part(src, 0, call_start)
                  suffix = binary_part(src, call_end, byte_size(src) - call_end)
                  prefix <> "Enum.uniq()" <> suffix
              end

            :error ->
              src
          end

        :nomatch ->
          src
      end
    end)
  end

  defp collect_fixes(ast) do
    {_ast, fixes} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [list_arg, init_acc, fun]} = node,
        fixes ->
          if manual_uniq?(init_acc, fun) do
            line = Keyword.get(meta, :line)
            list_str = Macro.to_string(list_arg)
            {node, [{line, :direct, list_str} | fixes]}
          else
            {node, fixes}
          end

        {:|>, _,
         [list_arg, {{:., meta, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [init_acc, fun]}]} =
            node,
        fixes ->
          if manual_uniq?(init_acc, fun) do
            line = Keyword.get(meta, :line)
            list_str = Macro.to_string(list_arg)
            kind = :pipe
            {node, [{line, kind, list_str} | fixes]}
          else
            {node, fixes}
          end

        node, fixes ->
          {node, fixes}
      end)

    fixes
  end

  defp line_byte_offset(source, target_line) do
    source
    |> String.split("\n")
    |> Enum.take(target_line - 1)
    |> Enum.reduce(0, fn line, offset -> offset + byte_size(line) + 1 end)
  end

  defp find_matching_paren(<<>>, _depth, _pos), do: :error

  defp find_matching_paren(<<?(, rest::binary>>, 0, pos) do
    find_matching_paren(rest, 1, pos + 1)
  end

  defp find_matching_paren(<<?(, rest::binary>>, depth, pos) do
    find_matching_paren(rest, depth + 1, pos + 1)
  end

  defp find_matching_paren(<<?), _rest::binary>>, 1, pos) do
    {:ok, pos + 1}
  end

  defp find_matching_paren(<<?), rest::binary>>, depth, pos) do
    find_matching_paren(rest, depth - 1, pos + 1)
  end

  defp find_matching_paren(<<?", rest::binary>>, depth, pos) do
    case skip_string(rest, pos + 1) do
      {:ok, new_pos, new_rest} -> find_matching_paren(new_rest, depth, new_pos)
      :error -> :error
    end
  end

  defp find_matching_paren(<<_c, rest::binary>>, depth, pos) do
    find_matching_paren(rest, depth, pos + 1)
  end

  defp skip_string(<<?", rest::binary>>, pos), do: {:ok, pos + 1, rest}
  defp skip_string(<<?\\, _c, rest::binary>>, pos), do: skip_string(rest, pos + 2)
  defp skip_string(<<>>, _pos), do: :error
  defp skip_string(<<_c, rest::binary>>, pos), do: skip_string(rest, pos + 1)

  defp manual_uniq?(init_acc, fun) do
    case find_mapset_index(init_acc) do
      nil -> false
      index -> matches_dedup_lambda?(fun, index)
    end
  end

  defp find_mapset_index({e1, e2}) do
    cond do
      mapset_init?(e1) -> 0
      mapset_init?(e2) -> 1
      true -> nil
    end
  end

  defp find_mapset_index(_), do: nil

  defp mapset_init?({{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, _, _}), do: true
  defp mapset_init?(_), do: false

  defp matches_dedup_lambda?({:fn, _, clauses}, ms_index) do
    Enum.any?(clauses, fn
      {:->, _, [[item_pattern, acc_pattern], body]} ->
        item_var = get_var_name(item_pattern)
        seen_var = get_var_name_at_index(acc_pattern, ms_index)

        if item_var && seen_var do
          conditional_dedup?(body, seen_var, item_var)
        else
          false
        end

      _ ->
        false
    end)
  end

  defp matches_dedup_lambda?(_, _), do: false

  defp get_var_name({name, _, nil}) when is_atom(name), do: name
  defp get_var_name(_), do: nil

  defp get_var_name_at_index({left, right}, index) do
    target = if index == 0, do: left, else: right
    get_var_name(target)
  end

  defp get_var_name_at_index(_, _), do: nil

  defp conditional_dedup?(body, seen_var, item_var) do
    {_, found?} =
      Macro.prewalk(body, false, fn
        {type, _, [condition | _]} = node, acc when type in [:if, :unless, :case] ->
          if uses_mapset_member?(condition, seen_var, item_var) do
            {node, true}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    found?
  end

  defp uses_mapset_member?(condition, seen_var, item_var) do
    case condition do
      {{:., _, [{:__aliases__, _, [:MapSet]}, :member?]}, _,
       [{^seen_var, _, nil}, {^item_var, _, nil}]} ->
        true

      {op, _, [inner]} when op in [:!, :not] ->
        uses_mapset_member?(inner, seen_var, item_var)

      _ ->
        false
    end
  end

  defp trigger_issue(meta) do
    %Issue{
      rule: :no_manual_enum_uniq,
      message: """
      Manual reimplementation of `Enum.uniq/1` detected.
      This pattern uses `Enum.reduce/3` with a `MapSet` to filter duplicates.
      This is significantly more verbose and less efficient than the built-in
      function.
      Consider using:
        Enum.uniq(list)
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
