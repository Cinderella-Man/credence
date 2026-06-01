defmodule Credence.Syntax.FixModuleAttrOutsideModule do
  @moduledoc """
  Fixes module attributes that appear outside a `defmodule` block.

  LLMs sometimes output `@moduledoc`, `@doc`, `@spec`, `@type`, and other
  module attributes at the file's top level — either before a `defmodule`
  block, or with no `defmodule` wrapper at all. This causes a compile error:

      cannot invoke @/1 outside module

  Two cases are handled:

  1. **Attrs before `defmodule`** — moves them inside the module block,
     matching the indentation of the body.
  2. **No `defmodule` at all** — wraps the entire content in
     `defmodule Solution do ... end`.

  Handles multi-line heredoc attributes (`@moduledoc """..."""`).
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  @known_attrs ~w(
    moduledoc doc spec type typep callback macrocallback impl
    derive enforce_keys behaviour on_definition before_compile
    after_compile vsn compile dialyzer file deprecated module_attribute
  )

  @impl true
  def analyze(source) do
    lines = String.split(source, "\n")

    case find_defmodule_idx(lines) do
      nil ->
        if Enum.any?(lines, &attr_line?/1) do
          [build_issue()]
        else
          []
        end

      defmodule_idx ->
        before = Enum.take(lines, defmodule_idx)

        if Enum.any?(before, &attr_line?/1) do
          [build_issue()]
        else
          []
        end
    end
  end

  @impl true
  def fix(source) do
    lines = String.split(source, "\n")

    case find_defmodule_idx(lines) do
      nil ->
        if Enum.any?(lines, &attr_line?/1) do
          wrap_in_defmodule(lines)
        else
          source
        end

      defmodule_idx ->
        {before, from_defmodule} = Enum.split(lines, defmodule_idx)
        {attr_lines, rest_before} = collect_trailing_attrs(before)

        if attr_lines == [] do
          source
        else
          indent = detect_inner_indent(from_defmodule)
          indented = indent_block(attr_lines, indent)
          [defmodule_line | remaining] = from_defmodule

          # Remove duplicate attrs already inside the module body
          moved_names = attr_names(attr_lines)
          deduped = remove_duplicate_attrs(remaining, moved_names, indent)

          (rest_before ++ [defmodule_line] ++ indented ++ deduped)
          |> Enum.join("\n")
        end
    end
  end

  # ── helpers ──────────────────────────────────────────────────────

  # When there is no `defmodule` at all but there are module attributes
  # at the top level, wrap everything in `defmodule Solution do ... end`.
  defp wrap_in_defmodule(lines) do
    # Strip trailing empty lines to avoid blank line before `end`
    trimmed = Enum.reverse(lines) |> Enum.drop_while(&(String.trim(&1) == "")) |> Enum.reverse()
    indent = "  "
    indented = indent_block(trimmed, indent)
    (["defmodule Solution do"] ++ indented ++ ["end"])
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp find_defmodule_idx(lines) do
    Enum.find_index(lines, &Regex.match?(~r/^\s*defmodule\s/, &1))
  end

  # Collect the trailing block of module-attribute lines (including heredoc
  # bodies) from the end of `lines`. Skips trailing blank lines between the
  # last attr and `defmodule`. Returns {attr_lines, remaining_lines}.
  defp collect_trailing_attrs(lines) do
    reversed = Enum.reverse(lines)

    # Skip trailing blank lines (between last attr and defmodule)
    non_blank = Enum.drop_while(reversed, &(String.trim(&1) == ""))

    # Scan backwards, prepending to acc → attrs end up in original order.
    # remaining_rev is tail-of-reversed, so it needs one more reverse.
    {attrs, remaining_rev} = do_collect_attrs(non_blank, :outside, [])
    {attrs, Enum.reverse(remaining_rev)}
  end

  # Finished scanning
  defp do_collect_attrs([], _state, acc), do: {acc, []}

  # Inside a heredoc (scanning backwards) — keep collecting until opening """
  defp do_collect_attrs([line | rest], :heredoc, acc) do
    if heredoc_open?(line) do
      # This is the opening """ line — include it and exit heredoc
      do_collect_attrs(rest, :outside, [line | acc])
    else
      do_collect_attrs(rest, :heredoc, [line | acc])
    end
  end

  # Outside heredoc — scanning from end towards start
  defp do_collect_attrs([line | rest], :outside, acc) do
    trimmed = String.trim(line)

    cond do
      # Closing """ of a heredoc — enter heredoc state
      trimmed == ~s(""") ->
        do_collect_attrs(rest, :heredoc, [line | acc])

      # Module attribute line — collect it
      attr_line?(trimmed) ->
        do_collect_attrs(rest, :outside, [line | acc])

      # Blank line between attrs — include it
      trimmed == "" and acc != [] ->
        do_collect_attrs(rest, :outside, [line | acc])

      # Anything else — stop collecting
      true ->
        {acc, [line | rest]}
    end
  end

  defp attr_line?(line) do
    trimmed = if is_binary(line), do: String.trim(line), else: line
    Enum.any?(@known_attrs, fn attr -> String.starts_with?(trimmed, "@#{attr} ") end)
  end

  # Extract the set of attr names from lines being moved (e.g. ["doc", "spec"])
  defp attr_names(lines) do
    lines
    |> Enum.map(fn line ->
      trimmed = String.trim(line)
      Enum.find_value(@known_attrs, fn attr ->
        if String.starts_with?(trimmed, "@#{attr} "), do: attr
      end)
    end)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  # Remove lines inside the module body that define attrs with the same names
  # as the ones being moved from outside. This prevents duplicate @doc, @spec, etc.
  defp remove_duplicate_attrs(body_lines, moved_names, _indent) do
    if MapSet.size(moved_names) == 0 do
      body_lines
    else
      do_remove_duplicates(body_lines, moved_names, false, [])
    end
  end

  # Finished scanning — reverse accumulated lines
  defp do_remove_duplicates([], _moved, _in_heredoc, acc), do: Enum.reverse(acc)

  # Inside a heredoc body — skip until closing """
  defp do_remove_duplicates([line | rest], moved, true, acc) do
    if String.trim(line) == ~s(""") do
      do_remove_duplicates(rest, moved, false, [line | acc])
    else
      do_remove_duplicates(rest, moved, true, acc)
    end
  end

  # Outside heredoc — check if this line is a duplicate attr
  defp do_remove_duplicates([line | rest], moved, false, acc) do
    trimmed = String.trim(line)

    cond do
      # Duplicate attr line (e.g. @doc false when we're moving @doc from outside)
      attr_line?(trimmed) and attr_name_matches?(trimmed, moved) ->
        # Skip this line and any following heredoc body
        if heredoc_open?(line) do
          do_remove_duplicates(rest, moved, true, acc)
        else
          do_remove_duplicates(rest, moved, false, acc)
        end

      # Non-duplicate line — keep it
      true ->
        do_remove_duplicates(rest, moved, false, [line | acc])
    end
  end

  defp attr_name_matches?(trimmed, moved_names) do
    Enum.any?(moved_names, fn attr -> String.starts_with?(trimmed, "@#{attr} ") end)
  end

  defp heredoc_open?(line) do
    trimmed = String.trim(line)
    # The opening line of a heredoc contains """ but is not just the closing """
    String.contains?(trimmed, ~s(""")) and trimmed != ~s(""")
  end

  defp detect_inner_indent(from_defmodule) do
    from_defmodule
    |> Enum.drop(1)
    |> Enum.find_value("  ", fn line ->
      case Regex.run(~r/^(\s+)/, line) do
        [_, indent] -> indent
        _ -> nil
      end
    end)
  end

  defp indent_block(lines, indent) do
    Enum.map(lines, fn line ->
      if String.trim(line) == "" do
        line
      else
        indent <> String.trim_leading(line)
      end
    end)
  end

  defp build_issue do
    %Issue{
      rule: :module_attr_outside_module,
      message:
        "Module attributes appear before `defmodule`. " <>
          "Move them inside the module block."
    }
  end
end
