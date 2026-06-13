defmodule Credence.Syntax.NoWhileKeyword do
  @moduledoc """
  Detects and rewrites Python-style `while <cond> do ... end` loops.

  LLMs translating from Python/Java emit `while` loops, which don't exist
  in Elixir. This rule converts them into tail-recursive helper functions
  using a guard clause on the positive condition and a catchall base case.

  ## Detected patterns

      while <condition> do
        <body>
      end

  ## Not flagged

  Valid Elixir constructs that don't use `while`:

      Enum.each(list, fn x -> ... end)
      Stream.iterate(0, &(&1 + 1))
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  @while_re ~r/^(\s*)while\s+(.+?)\s+do\s*$/
  @assign_re ~r/^\s*([A-Za-z_]\w*)\s*=\s*.+$/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if Regex.match?(@while_re, line) do
        [%Issue{
          rule: :no_while_keyword,
          message: "Elixir has no `while` loop. Use tail recursion instead.",
          meta: %{line: line_no}
        }]
      else
        []
      end
    end)
  end

  @impl true
  def fix(source) do
    case find_while(source) do
      {:ok, ctx} -> apply_fix(source, ctx)
      :not_found -> source
    end
  end

  # --- Finding the while block ---

  defp find_while(source) do
    lines = String.split(source, "\n")
    search_lines(lines, 0, source)
  end

  defp search_lines([], _i, _src), do: :not_found

  defp search_lines([line | rest], i, src) do
    case Regex.run(@while_re, line) do
      [_, indent, cond] ->
        {body_lines, end_offset} = collect_end(rest, 1)
        fun_name = find_enclosing_fun(src, i)

        {:ok, %{
          idx: i,
          end_idx: i + end_offset,
          indent: indent,
          cond: cond,
          body_lines: body_lines,
          fun_name: fun_name
        }}

      nil ->
        search_lines(rest, i + 1, src)
    end
  end

  defp collect_end(lines, depth), do: collect_end(lines, depth, 0)

  defp collect_end([], _d, n), do: {[], n}

  defp collect_end([line | rest], d, n) do
    nd = d + kw_count(line, "do") - kw_count(line, "end")
    if nd <= 0 do
      {[], n + 1}
    else
      {bl, ei} = collect_end(rest, nd, n + 1)
      {[line | bl], ei}
    end
  end

  defp kw_count(line, "do") do
    Regex.scan(~r/(?<![A-Za-z_])do(?!:|\w)/, line) |> length()
  end

  defp kw_count(line, "end") do
    Regex.scan(~r/(?<![A-Za-z_])end(?![A-Za-z_])/, line) |> length()
  end

  defp find_enclosing_fun(src, while_idx) do
    src
    |> String.split("\n")
    |> Enum.take(while_idx)
    |> Enum.reverse()
    |> Enum.find_value(fn line ->
      case Regex.run(~r/^(\s*)defp?\s+([a-zA-Z_]\w*)\s*\(([^)]*)\)/, line) do
        [_, indent, name, params] -> {name, indent, parse_params(params)}
        nil -> nil
      end
    end)
  end

  defp parse_params(params_str) do
    params_str
    |> String.split(",")
    |> Enum.map(fn p ->
      p |> String.trim() |> String.split("\\") |> hd() |> String.trim()
    end)
    |> Enum.reject(&(&1 == ""))
  end

  # --- Applying the fix ---

  defp apply_fix(source, ctx) do
    lines = String.split(source, "\n")
    prefix = Enum.take(lines, ctx.idx)
    rest = Enum.drop(lines, ctx.end_idx + 1)

    # Find trailing assignments before the while that are also reassigned in the body
    {prefix_assigns, consumed} = trailing_assignments(prefix, ctx.body_lines)
    remaining_prefix = Enum.take(prefix, length(prefix) - consumed)

    # Find body assignments (variables reassigned in the loop body)
    body_assigns = body_assignments(ctx.body_lines)

    # Merge: prefix assigns come first, then body assigns not already covered
    prefix_vars = for {v, _} <- prefix_assigns, do: v
    all_vars =
      prefix_assigns ++
      Enum.filter(body_assigns, fn {v, _} -> v not in prefix_vars end)

    # Separate accumulator (returned after while) from loop vars
    {loop_vars, accum} = separate_accum(all_vars, rest, ctx)

    # Build helper
    helper = build_helper(ctx, loop_vars, accum)

    # Build call to helper from the enclosing function
    call = build_call(ctx, loop_vars, accum)

    # Insert helper right after the enclosing function's closing `end`.
    fun_indent = case ctx.fun_name do
      {_, indent, _} -> indent <> "end"
      nil -> "end"
    end
    {before_end, after_end} = split_at_fun_end(rest, fun_indent)

    # Remove accumulator return expression between while end and function end.
    # The helper call replaces both the while loop and the return value.
    accum_name = if accum, do: elem(accum, 0), else: nil
    filtered_before_end =
      if accum_name do
        Enum.reject(before_end, fn line ->
          trimmed = String.trim(line)
          trimmed == accum_name
        end)
      else
        before_end
      end

    (remaining_prefix ++ [call] ++ filtered_before_end ++ [helper] ++ after_end)
    |> Enum.join("\n")
    |> ensure_newline()
  end

  defp separate_accum(all_vars, lines_after_while, _ctx) do
    case all_vars do
      [] ->
        {[], nil}
      [_single] ->
        {[], hd(all_vars)}
      _multiple ->
        # The accumulator is the variable returned after the while loop
        after_text = Enum.join(lines_after_while, "\n")
        {rev_loop, found_accum} =
          Enum.reduce(Enum.reverse(all_vars), {[], nil}, fn
            var, {loop, acc} when acc != nil -> {[var | loop], acc}
            {v, init}, {loop, nil} ->
              if Regex.match?(~r/\b#{Regex.escape(v)}\b/, after_text) do
                {loop, {v, init}}
              else
                {[{v, init} | loop], nil}
              end
          end)

        case found_accum do
          nil ->
            # No variable found in return; use last as accumulator
            {Enum.drop(all_vars, -1), List.last(all_vars)}
          _ ->
            {Enum.reverse(rev_loop), found_accum}
        end
    end
  end

  defp trailing_assignments(prefix_lines, body_lines) do
    body_text = Enum.join(body_lines, "\n")

    trailing =
      prefix_lines
      |> Enum.reverse()
      |> Enum.take_while(fn line ->
        trimmed = String.trim(line)
        trimmed != "" and Regex.match?(@assign_re, trimmed)
      end)
      |> Enum.reverse()

    relevant =
      trailing
      |> Enum.flat_map(fn line ->
        trimmed = String.trim(line)
        case Regex.run(@assign_re, trimmed) do
          [_, var] ->
            if Regex.match?(~r/\b#{Regex.escape(var)}\s*=\s/, body_text) do
              init = extract_rhs(trimmed)
              [{var, init}]
            else
              []
            end
          nil -> []
        end
      end)

    {relevant, length(trailing)}
  end

  defp body_assignments(body_lines) do
    body_text = Enum.join(body_lines, "\n")

    body_lines
    |> Enum.flat_map(fn line ->
      case Regex.run(@assign_re, line) do
        [_, var] ->
          esc = Regex.escape(var)
          assigns = Regex.scan(~r/#{esc}\s*=/, body_text)
          self_ref = Regex.match?(~r/#{esc}\s*=.*\b#{esc}\b/, line)
          if length(assigns) > 1 or self_ref do
            [{var, "nil"}]
          else
            []
          end
        nil -> []
      end
    end)
    |> Enum.uniq_by(fn {v, _} -> v end)
  end

  defp extract_rhs(line) do
    case Regex.run(~r/^\s*[A-Za-z_]\w*\s*=\s*(.+)$/, line) do
      [_, rhs] -> String.trim(rhs)
      nil -> "nil"
    end
  end

  defp build_call(ctx, loop_vars, accum) do
    enc_params = case ctx.fun_name do
      {_, _, params} -> params
      nil -> []
    end
    all_var_names = (for {v, _} <- loop_vars, do: v) ++ (if accum, do: [elem(accum, 0)], else: [])
    free_vars = Enum.reject(enc_params, &(&1 in all_var_names))
    init_vals = (for {_, init} <- loop_vars, do: init) ++ (if accum, do: [elem(accum, 1)], else: [])
    all_args = free_vars ++ init_vals
    name = case ctx.fun_name do
      {n, _, _} -> "do_#{n}"
      nil -> "do_loop"
    end
    call_indent = ctx.indent
    "#{call_indent}#{name}(#{Enum.join(all_args, ", ")})"
  end

  defp build_helper(ctx, loop_vars, accum) do
    {fun_name, def_indent, enc_params} = case ctx.fun_name do
      {name, indent, params} -> {"do_#{name}", indent, params}
      nil -> {"do_loop", ctx.indent, []}
    end
    body_i = def_indent <> "  "

    all_var_names = (for {v, _} <- loop_vars, do: v) ++ (if accum, do: [elem(accum, 0)], else: [])
    free_vars = Enum.reject(enc_params, &(&1 in all_var_names))

    # Parameters: free_vars, then loop_vars, then accum
    params = Enum.join(free_vars ++ all_var_names, ", ")
    args = Enum.join(free_vars ++ all_var_names, ", ")
    name = fun_name

    # Base case: catchall with underscored vars, accumulator bound, returns accum init
    base_params_list =
      free_vars ++
      Enum.map(loop_vars, fn {v, _} -> "_#{v}" end) ++
      (if accum, do: [elem(accum, 0)], else: [])

    base_params = Enum.join(base_params_list, ", ")
    # Return the accumulator variable name (its current value), not its initial value
    last_val = if accum, do: elem(accum, 0), else: "nil"

    # Re-indent body lines
    body_src_indent = ctx.indent <> "  "
    reindented =
      ctx.body_lines
      |> Enum.map(fn line ->
        case String.starts_with?(line, body_src_indent) do
          true -> body_i <> String.replace_prefix(line, body_src_indent, "")
          false -> body_i <> String.trim_leading(line)
        end
      end)
      |> Enum.join("\n")

    # Catchall first (no guard), then recursive case with positive guard
    "#{def_indent}defp #{name}(#{base_params}), do: #{last_val}\n" <>
    "#{def_indent}defp #{name}(#{params}) when #{ctx.cond} do\n" <>
    "#{reindented}\n" <>
    "#{body_i}#{name}(#{args})\n" <>
    "#{def_indent}end"
  end

  defp split_at_fun_end(lines, end_pattern) do
    idx = Enum.find_index(lines, &(String.trim(&1) == String.trim(end_pattern)))
    case idx do
      nil -> {lines, []}
      i -> {Enum.take(lines, i + 1), Enum.drop(lines, i + 1)}
    end
  end

  defp ensure_newline(s) do
    if String.ends_with?(s, "\n"), do: s, else: s <> "\n"
  end
end
