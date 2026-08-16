defmodule Credence.Pattern.NoCaptureFnApply do
  @moduledoc """
  Detects capture expressions that are immediately applied with `.()`.

  When a capture `&` with positional placeholders (`&1`, `&2`, …) is
  immediately applied via `.()`, the result is harder to read than
  inlining the arguments directly into the expression.

  ## Bad

      defmodule Grid do
        def cell(el, col), do: (&Enum.at(&1, col)).(el)
        def add(a, b), do: (& &1 + &2).(a, b)
      end

  ## Good

      defmodule Grid do
        def cell(el, col), do: Enum.at(el, col)
        def add(a, b), do: a + b
      end
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., meta, [{:&, _, [capture_body]}]}, _, apply_args} = node, issues ->
          if has_placeholders?(capture_body, length(apply_args)) and safe_args?(apply_args) do
            issue = %Issue{
              rule: :no_capture_fn_apply,
              message:
                "Avoid applying a capture with `.()` immediately. " <>
                  "Inline the arguments directly into the expression instead.",
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
    source = Keyword.get(opts, :source, "")

    {_ast, {patches, _seen_lines}} =
      Macro.prewalk(ast, {[], MapSet.new()}, fn
        {{:., _, [{:&, amp_meta, [capture_body]}]}, _, apply_args} = node,
        {patches, seen_lines} ->
          line = Keyword.get(amp_meta, :line)

          if has_placeholders?(capture_body, length(apply_args)) and
               safe_args?(apply_args) and
               not MapSet.member?(seen_lines, line) do
            inlined = inline_placeholders(capture_body, apply_args)
            replacement = Sourceror.to_string(inlined)

            case Sourceror.get_range(node) do
              %{start: start_pos, end: end_pos} ->
                # Extend range to include surrounding (...) parens around capture
                adjusted_start =
                  case find_opening_paren(source, start_pos) do
                    nil -> start_pos
                    paren_pos -> paren_pos
                  end

                adjusted_end =
                  case find_closing_paren(source, end_pos) do
                    nil -> end_pos
                    paren_pos -> paren_pos
                  end

                patch = %{
                  range: %{start: adjusted_start, end: adjusted_end},
                  change: replacement
                }

                range_lines =
                  start_pos[:line]..end_pos[:line] |> Enum.into(MapSet.new())

                {node, {[patch | patches], MapSet.union(seen_lines, range_lines)}}

              _ ->
                {node, {patches, seen_lines}}
            end
          else
            {node, {patches, seen_lines}}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(patches)
  end

  # Check if there's a '(' right before the start position
  defp find_opening_paren(source, pos) do
    lines = String.split(source, "\n")
    line_idx = pos[:line] - 1
    col = pos[:column] - 1

    case Enum.at(lines, line_idx) do
      nil ->
        nil

      line_text ->
        before = String.slice(line_text, 0, col)
        trimmed = String.trim_trailing(before)

        if String.ends_with?(trimmed, "(") do
          paren_col = byte_size(trimmed)
          [line: pos[:line], column: paren_col]
        else
          nil
        end
    end
  end

  # Check if there's a ')' right after the end position
  defp find_closing_paren(source, pos) do
    lines = String.split(source, "\n")
    line_idx = pos[:line] - 1
    col = pos[:column] - 1

    case Enum.at(lines, line_idx) do
      nil ->
        nil

      line_text ->
        after_text = String.slice(line_text, col, byte_size(line_text) - col)
        trimmed = String.trim_leading(after_text)

        if String.starts_with?(trimmed, ")") do
          # Find the column of the ')'
          offset = byte_size(after_text) - byte_size(trimmed)
          paren_col = col + offset + 1
          [line: pos[:line], column: paren_col + 1]
        else
          nil
        end
    end
  end

  # Inlining substitutes each apply arg into its &N placeholder positions. That is only
  # behaviour-preserving when every arg is *pure* (a bare variable or a scalar literal):
  # then duplicating an arg (placeholder used twice), dropping one (placeholder unused), and
  # reordering them (placeholders out of arg order) are all unobservable. An arg with side
  # effects or its own evaluation cost would change the answer under any of those, so we only
  # fire on pure args.
  defp safe_args?(args), do: Enum.all?(args, &pure_arg?/1)

  # A scalar literal: Sourceror wraps literals as {:__block__, _, [value]}.
  defp pure_arg?({:__block__, _, [value]}),
    do: is_number(value) or is_atom(value) or is_binary(value)

  # A bare variable: {name, _, context} where context is an atom (calls carry a list here).
  defp pure_arg?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp pure_arg?(_), do: false

  # Returns true if the capture body contains &N placeholders (not &Module.fun/arity refs).
  defp has_placeholders?(body, arity) do
    {_found, result} =
      Macro.prewalk(body, false, fn
        {:&, _, [n]}, _acc when is_integer(n) and n >= 1 and n <= arity -> {nil, true}
        node, acc -> {node, acc}
      end)

    result
  end

  # Walk the capture body and replace &N placeholders with the Nth apply arg.
  defp inline_placeholders(body, apply_args) do
    Macro.prewalk(body, fn
      {:&, _, [n]} when is_integer(n) and n >= 1 and n <= length(apply_args) ->
        Enum.at(apply_args, n - 1)

      other ->
        other
    end)
  end
end
