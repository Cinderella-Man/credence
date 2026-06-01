defmodule Credence.Syntax.FixTypespecLiteralList do
  @moduledoc """
  Fixes literal lists used as types in `@spec` return types.

  LLMs translating from Python sometimes write `[pos_integer(), pos_integer()]`
  as a typespec return type, which is invalid Elixir syntax. In Elixir typespecs,
  `[type]` means "a list of type" (single element type), and `[type, type]` with
  multiple comma-separated elements is not valid.

  This rule converts such literal lists to tuple types, which is the idiomatic
  Elixir way to express fixed-size heterogeneous types:

      @spec foo(integer()) :: [pos_integer(), pos_integer()]
      # becomes
      @spec foo(integer()) :: {pos_integer(), pos_integer()}
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if literal_list_return_type?(line), do: [build_issue(line_no)], else: []
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.map_join("\n", &fix_line/1)
  end

  # ── detection ────────────────────────────────────────────────────

  defp literal_list_return_type?(line) do
    case extract_return_type(line) do
      {:ok, return_type} -> literal_list?(String.trim(return_type))
      :skip -> false
    end
  end

  # ── fix ──────────────────────────────────────────────────────────

  defp fix_line(line) do
    case extract_return_type_with_pos(line) do
      {:ok, prefix, return_type} ->
        trimmed = String.trim_leading(return_type)
        leading_space = binary_part(return_type, 0, byte_size(return_type) - byte_size(trimmed))

        if literal_list?(trimmed) do
          inner = String.slice(trimmed, 1, String.length(trimmed) - 2)
          prefix <> leading_space <> "{" <> inner <> "}"
        else
          line
        end

      :skip ->
        line
    end
  end

  # ── return type extraction ───────────────────────────────────────

  defp extract_return_type(line) do
    case extract_return_type_with_pos(line) do
      {:ok, _prefix, return_type} -> {:ok, return_type}
      :skip -> :skip
    end
  end

  defp extract_return_type_with_pos(line) do
    trimmed = String.trim_leading(line)

    if String.starts_with?(trimmed, "@spec ") do
      chars = String.to_charlist(line)

      case find_double_colon(chars, 0, 0) do
        {:ok, pos} ->
          prefix = String.slice(line, 0, pos + 2)
          return_type = String.slice(line, pos + 2, String.length(line))
          {:ok, prefix, return_type}

        :not_found ->
          :skip
      end
    else
      :skip
    end
  end

  # Find `::` at paren/bracket depth 0. Returns the character position.
  defp find_double_colon([], _depth, _pos), do: :not_found
  defp find_double_colon([?:, ?: | _rest], 0, pos), do: {:ok, pos}
  defp find_double_colon([?( | rest], depth, pos), do: find_double_colon(rest, depth + 1, pos + 1)
  defp find_double_colon([?) | rest], depth, pos), do: find_double_colon(rest, depth - 1, pos + 1)
  defp find_double_colon([?[ | rest], depth, pos), do: find_double_colon(rest, depth + 1, pos + 1)
  defp find_double_colon([?] | rest], depth, pos), do: find_double_colon(rest, depth - 1, pos + 1)
  defp find_double_colon([?{ | rest], depth, pos), do: find_double_colon(rest, depth + 1, pos + 1)
  defp find_double_colon([?} | rest], depth, pos), do: find_double_colon(rest, depth - 1, pos + 1)
  defp find_double_colon([_ | rest], depth, pos), do: find_double_colon(rest, depth, pos + 1)

  # ── literal list detection ───────────────────────────────────────

  # Returns true if the type string is a literal list with multiple elements,
  # i.e. starts with `[` and contains a comma at bracket depth 0.
  defp literal_list?(type_str) do
    case String.first(type_str) do
      "[" ->
        inner = String.slice(type_str, 1, String.length(type_str) - 2)
        has_comma_at_depth_zero?(inner)

      _ ->
        false
    end
  end

  defp has_comma_at_depth_zero?(str), do: do_check_comma(String.to_charlist(str), 0)

  defp do_check_comma([], _depth), do: false
  defp do_check_comma([?, | _rest], 0), do: true
  defp do_check_comma([?( | rest], depth), do: do_check_comma(rest, depth + 1)
  defp do_check_comma([?) | rest], depth), do: do_check_comma(rest, depth - 1)
  defp do_check_comma([?[ | rest], depth), do: do_check_comma(rest, depth + 1)
  defp do_check_comma([?] | rest], depth), do: do_check_comma(rest, depth - 1)
  defp do_check_comma([?{ | rest], depth), do: do_check_comma(rest, depth + 1)
  defp do_check_comma([?} | rest], depth), do: do_check_comma(rest, depth - 1)
  defp do_check_comma([_ | rest], depth), do: do_check_comma(rest, depth)

  # ── issue ────────────────────────────────────────────────────────

  defp build_issue(line_no) do
    %Issue{
      rule: :typespec_literal_list,
      message:
        "Literal list `[type, type]` in typespec return type is invalid Elixir. " <>
          "Use a tuple `{type, type}` for fixed-size types, or `[type]` for a list type.",
      meta: %{line: line_no}
    }
  end
end
