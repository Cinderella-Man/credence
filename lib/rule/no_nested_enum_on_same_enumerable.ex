defmodule Credence.Rule.NoNestedEnumOnSameEnumerable do
  @moduledoc """
  Detects `Enum.member?/2` calls nested inside another `Enum.*` traversal
  of the **same** enumerable and rewrites them to use `MapSet.member?/2`.

  ## Bad
      Enum.map(list, fn x ->
        Enum.member?(list, x + 1)
      end)

  ## Good
      set = MapSet.new(list)

      Enum.map(list, fn x ->
        MapSet.member?(set, x + 1)
      end)
  """

  use Credence.Rule
  alias Credence.Issue

  @enum_funcs [
    :map,
    :filter,
    :reduce,
    :count,
    :any?,
    :all?,
    :find,
    :find_value,
    :member?
  ]

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, {_, issues}} =
      Macro.prewalk(ast, {[], []}, fn node, {stack, issues} ->
        case extract_enum_call(node) do
          {:ok, func, var, meta} ->
            new_issues =
              if Enum.any?(stack, fn {_f, v} -> v == var end) do
                [
                  %Issue{
                    rule: :no_nested_enum_on_same_enumerable,
                    message: build_message(func, var),
                    meta: %{line: Keyword.get(meta, :line)}
                  }
                ]
              else
                []
              end

            {node, {[{func, var} | stack], issues ++ new_issues}}

          _ ->
            {node, {stack, issues}}
        end
      end)

    issues
  end

  @impl true
  def fix(source, _opts) do
    ast = Sourceror.parse_string!(source)
    outer_calls = collect_outer_calls(ast, source)

    Enum.reduce(outer_calls, source, fn {start_kw, end_kw, outer_var}, acc ->
      fix_single_outer_call(acc, start_kw, end_kw, outer_var)
    end)
  end

  defp collect_outer_calls(ast, source) do
    {_ast, calls} =
      Macro.prewalk(ast, [], fn node, acc ->
        case extract_enum_call(node) do
          {:ok, func, var, _meta} when func != :member? ->
            case get_node_range(node, source) do
              {:ok, start_kw, end_kw} ->
                {node, acc ++ [{start_kw, end_kw, var}]}

              :error ->
                {node, acc}
            end

          _ ->
            {node, acc}
        end
      end)

    calls
  end

  defp get_node_range(node, source) do
    case Sourceror.get_range(node) do
      %Sourceror.Range{start: start_kw, end: end_kw} ->
        {:ok, start_kw, end_kw}

      _other ->
        compute_range_from_metadata(node, source)
    end
  end

  defp compute_range_from_metadata(
         {{:., _, [{:__aliases__, _, [:Enum]}, _func]}, meta, _args},
         source
       ) do
    start_line = Keyword.get(meta, :line)
    start_col = Keyword.get(meta, :column)

    if start_line && start_col do
      start_byte = line_col_to_byte(source, start_line, start_col)
      end_byte = find_matching_close(source, start_byte)

      if end_byte do
        {end_line, end_col} = byte_to_line_col(source, end_byte)
        {:ok, [line: start_line, column: start_col], [line: end_line, column: end_col]}
      else
        :error
      end
    else
      :error
    end
  end

  defp compute_range_from_metadata(_, _), do: :error

  # ── Find the byte position of the matching ')' ─────────────────────
  defp find_matching_close(source, start_byte) do
    remaining = binary_part(source, start_byte, byte_size(source) - start_byte)

    case do_find_close(remaining, 0, 0) do
      nil -> nil
      offset -> start_byte + offset
    end
  end

  # Walk through the string tracking parenthesis depth.
  # Returns the offset (from the start of `remaining`) of the closing ')'.
  defp do_find_close(<<>>, _depth, _pos), do: nil

  defp do_find_close(<<?(, rest::binary>>, depth, pos) do
    do_find_close(rest, depth + 1, pos + 1)
  end

  defp do_find_close(<<?)>>, depth, pos) when depth == 1, do: pos + 1

  defp do_find_close(<<?), rest::binary>>, depth, pos) when depth > 0 do
    if depth == 1 do
      # This ')' closes the outermost '(' — return position just past it
      pos + 1
    else
      do_find_close(rest, depth - 1, pos + 1)
    end
  end

  defp do_find_close(<<_, rest::binary>>, depth, pos) do
    do_find_close(rest, depth, pos + 1)
  end

  defp line_col_to_byte(source, line, col) do
    lines = String.split(source, "\n")

    byte_offset =
      lines
      |> Enum.take(line - 1)
      |> Enum.map(&(byte_size(&1) + 1))
      |> Enum.sum()

    byte_offset + (col - 1)
  end

  defp byte_to_line_col(source, byte) do
    before = binary_part(source, 0, byte)
    lines = String.split(before, "\n")
    line = length(lines)
    col = byte_size(List.last(lines)) + 1
    {line, col}
  end

  defp fix_single_outer_call(source, start_kw, end_kw, outer_var) do
    {start_byte, end_byte} = range_to_bytes(source, start_kw, end_kw)

    if start_byte >= end_byte or end_byte > byte_size(source) do
      source
    else
      outer_text = binary_part(source, start_byte, end_byte - start_byte)
      member_calls = find_member_calls_in_range(outer_text, outer_var)

      if member_calls == [] do
        source
      else
        indent = get_indent(source, start_byte)
        var_str = Atom.to_string(outer_var)

        new_code =
          "#{indent}set = MapSet.new(#{var_str})\n" <>
            replace_member_calls(outer_text, member_calls)

        binary_part(source, 0, start_byte) <>
          new_code <>
          binary_part(source, end_byte, byte_size(source) - end_byte)
      end
    end
  end

  defp replace_member_calls(text, member_calls) do
    {result, _offset} =
      Enum.reduce(member_calls, {text, 0}, fn {rel_start, rel_end, value_arg}, {acc, offset} ->
        abs_start = rel_start + offset
        abs_end = rel_end + offset
        new = "MapSet.member?(set, #{value_arg})"
        byte_diff = byte_size(new) - (abs_end - abs_start)

        updated =
          binary_part(acc, 0, abs_start) <>
            new <>
            binary_part(acc, abs_end, byte_size(acc) - abs_end)

        {updated, offset + byte_diff}
      end)

    result
  end

  defp find_member_calls_in_range(text, target_var) do
    var_str = Atom.to_string(target_var)

    ~r/Enum\.member\?\(\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*,\s*(.+?)\s*\)/
    |> Regex.scan(text, return: :index, capture: :all)
    |> Enum.filter(fn [{_match_pos, _match_len}, {v_pos, v_len} | _rest] ->
      binary_part(text, v_pos, v_len) == var_str
    end)
    |> Enum.map(fn [{match_pos, match_len}, _var, {val_pos, val_len}] ->
      val = binary_part(text, val_pos, val_len)
      {match_pos, match_pos + match_len, val}
    end)
  end

  defp build_message(:member?, var) do
    """
    Enum.member?/2 is used inside a traversal of `#{var}`, resulting in O(n²) complexity.
    Convert the list to a MapSet for O(1) lookups:
        set = MapSet.new(#{var})
        Enum.map(#{var}, fn x -> MapSet.member?(set, ...) end)
    """
  end

  defp build_message(:filter, var) do
    """
    Enum.filter/2 is nested inside another traversal of `#{var}`, causing O(n²) complexity.
    Avoid filtering the same list repeatedly. Consider:
    • Precomputing results once
    • Sorting and using indexed access
    • Combining logic into a single Enum.reduce/3 pass
    """
  end

  defp build_message(func, var) do
    """
    Nested Enum.#{func} call on `#{var}` detected.
    This results in O(n²) complexity due to repeated full traversals.
    Consider:
    • Precomputing reusable data outside the loop
    • Using a single Enum.reduce/3 pass
    • Avoiding repeated scans of the same list
    """
  end

  defp extract_enum_call({{:., _, [{:__aliases__, _, [:Enum]}, func]}, meta, [arg | _]})
       when func in @enum_funcs do
    case var_name(arg) do
      nil -> :error
      var -> {:ok, func, var, meta}
    end
  end

  defp extract_enum_call(_), do: :error

  defp var_name({name, _, context}) when is_atom(name) and is_atom(context), do: name
  defp var_name(_), do: nil

  defp range_to_bytes(source, start_kw, end_kw) do
    {
      line_col_to_byte(
        source,
        Keyword.get(start_kw, :line, 1),
        Keyword.get(start_kw, :column, 1)
      ),
      line_col_to_byte(source, Keyword.get(end_kw, :line, 1), Keyword.get(end_kw, :column, 1))
    }
  end

  defp get_indent(source, byte_pos) do
    before = binary_part(source, 0, byte_pos)

    case Regex.run(~r/\n([ \t]*)$/, before) do
      [_, indent] -> indent
      _ -> ""
    end
  end
end
