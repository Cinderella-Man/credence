defmodule Credence.Syntax.FixModuleAttrOutsideModule do
  @moduledoc """
  Fixes module attributes that appear before the `defmodule` declaration.

  LLMs sometimes output `@moduledoc`, `@doc`, `@spec`, `@type`, and other
  module attributes at the file's top level — before the `defmodule` block.
  This causes a compile error:

      cannot invoke @/1 outside module

  The rule detects module attributes that precede the first `defmodule` and
  moves them inside the module block, matching the indentation of the body.

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
        []

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
        source

      defmodule_idx ->
        {before, from_defmodule} = Enum.split(lines, defmodule_idx)
        {attr_lines, rest_before} = collect_trailing_attrs(before)

        if attr_lines == [] do
          source
        else
          indent = detect_inner_indent(from_defmodule)
          indented = indent_block(attr_lines, indent)
          [defmodule_line | remaining] = from_defmodule

          (rest_before ++ [defmodule_line] ++ indented ++ remaining)
          |> Enum.join("\n")
        end
    end
  end

  # ── helpers ──────────────────────────────────────────────────────

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
