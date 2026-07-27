defmodule Credence.Syntax.FixInlineKeywordIfInWithClause do
  @moduledoc """
  Repairs the common LLM syntax error where a keyword-syntax `if`
  (`do:`/`else:`) appears inside a `with` clause binding, causing a parse error.

  When an LLM writes:

      with ref <- if cond, do: a, else: b, ... do

  the Elixir parser treats the trailing comma after the keyword list as a
  `with`-binding separator (not `if` syntax), yielding
  "unexpected expression after keyword list".

  The deterministic fix moves the `if` from the binding into the `do`-body
  as an assignment:

      with ... do
        ref = if cond, do: a, else: b
        ...
      end

  ## Bad (won't parse — "unexpected expression after keyword list")

      with {:ok, items} <- parse(list),
           ref <- if item_ref(opts), do: item_ref(opts), else: nil,
           parent <- if parent_ref(opts), do: parent_ref(opts), else: nil do
        {:ok, ref, parent}
      end

  ## Good

      with {:ok, items} <- parse(list) do
        ref = if item_ref(opts), do: item_ref(opts), else: nil
        parent = if parent_ref(opts), do: parent_ref(opts), else: nil
        {:ok, ref, parent}
      end
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @error_fragment "unexpected expression after keyword list"

  # Matches a with-binding line that contains a keyword-style `if` (with do:/else:)
  # followed by a trailing comma or ` do` (the last binding before the do-block).
  # The trailing comma is what causes the parser ambiguity.
  @binding_with_keyword_if ~r/^[^<]*<-[^,]*\bif\b.*(,\s*$|\bdo\s*$)/

  @impl true
  def analyze(source) do
    case Code.string_to_quoted(source) do
      {:error, {meta, msg, _token}} when is_list(meta) ->
        if String.contains?(to_string(msg), @error_fragment) and
             String.contains?(source, "with ") do
          [
            %Issue{
              rule: :fix_inline_keyword_if_in_with_clause,
              message: to_string(msg),
              meta: %{line: Keyword.get(meta, :line)}
            }
          ]
        else
          []
        end

      _ ->
        []
    end
  end

  @impl true
  def fix(source) do
    case Code.string_to_quoted(source) do
      {:error, {meta, msg, _token}} when is_list(meta) ->
        if String.contains?(to_string(msg), @error_fragment) and
             String.contains?(source, "with ") do
          do_fix(source)
        else
          source
        end

      _ ->
        source
    end
  end

  defp do_fix(source) do
    lines = String.split(source, "\n")

    case find_with_block(lines) do
      {:ok, with_idx, do_idx} ->
        binding_lines = Enum.slice(lines, with_idx..do_idx)

        problematic =
          binding_lines
          |> Enum.with_index(with_idx)
          |> Enum.filter(fn {line, _idx} ->
            Regex.match?(@binding_with_keyword_if, String.trim_trailing(line))
          end)
          |> Enum.map(fn {_line, idx} -> idx end)

        case problematic do
          [] ->
            source

          _ ->
            move_bindings_to_do_body(lines, with_idx, do_idx, problematic)
        end

      :error ->
        source
    end
  end

  # Find the with-block: the line containing `with` keyword and the line ending with `do`
  defp find_with_block(lines) do
    with_idx = Enum.find_index(lines, &String.contains?(&1, "with "))

    if with_idx do
      do_idx =
        with_idx..(length(lines) - 1)
        |> Enum.find(with_idx, fn idx ->
          line = Enum.at(lines, idx)
          String.contains?(line, "<-") and Regex.match?(~r/ do(?![:\w])/, line)
        end)

      {:ok, with_idx, do_idx}
    else
      :error
    end
  end

  defp move_bindings_to_do_body(lines, with_idx, do_idx, problematic_indices) do
    do_body_indent = detect_do_body_indent(lines, do_idx)

    # Convert problematic binding lines to assignments with correct indentation
    moved_lines =
      problematic_indices
      |> Enum.map(fn idx ->
        line = Enum.at(lines, idx)
        convert_to_assignment(line, do_body_indent)
      end)

    # Build the remaining binding lines (non-problematic ones before do)
    remaining_indices = with_idx..do_idx |> Enum.reject(&(&1 in problematic_indices))

    remaining_lines =
      case Enum.to_list(remaining_indices) do
        [] ->
          # All bindings are problematic; add `do` to the with line
          [with_line] = [Enum.at(lines, with_idx)]
          [with_line <> " do"]

        indices ->
          last_idx = Enum.max(indices)

          Enum.map(indices, fn idx ->
            line = Enum.at(lines, idx)

            if idx == last_idx do
              # Last remaining binding: strip trailing comma, add ` do`
              line
              |> String.trim_trailing()
              |> strip_trailing_comma()
              |> Kernel.<>(" do")
            else
              line
            end
          end)
      end

    # Build the new content: everything before with + remaining bindings + moved + after do
    before_with = Enum.take(lines, with_idx)
    after_do = Enum.drop(lines, do_idx + 1)

    (before_with ++ remaining_lines ++ moved_lines ++ after_do)
    |> Enum.join("\n")
  end

  # Detect the indentation of content inside the do block
  defp detect_do_body_indent(lines, do_idx) do
    case Enum.at(lines, do_idx + 1) do
      nil ->
        with_line = Enum.at(lines, max(do_idx - 1, 0)) || ""
        leading_spaces(with_line) + 2

      next_line ->
        indent = leading_spaces(next_line)

        if indent > 0 do
          indent
        else
          with_line = Enum.at(lines, max(do_idx - 1, 0)) || ""
          leading_spaces(with_line) + 2
        end
    end
  end

  # Convert a binding line with `<-` to an assignment with `=`
  # Also re-indent to match the do-body indentation and strip trailing `do`/comma
  defp convert_to_assignment(line, target_indent) do
    new_indent = String.duplicate(" ", target_indent)

    converted =
      line
      |> String.trim_trailing()
      # If this is the last binding line, it ends with "do" — strip it
      |> strip_trailing_do()
      |> strip_trailing_comma()
      |> String.trim_leading()
      |> String.replace(~r/<-/, "=", global: false)

    new_indent <> converted
  end

  # Strip trailing ` do` keyword (the block delimiter, not keyword-syntax do:)
  defp strip_trailing_do(line) do
    # Match " do" followed by end of string (not "do:" keyword syntax)
    case Regex.run(~r/(.*?)\s+do\s*$/, line) do
      [_, prefix] -> prefix
      _ -> line
    end
  end

  defp strip_trailing_comma(line) do
    trimmed = String.trim_trailing(line)

    if String.ends_with?(trimmed, ",") do
      String.trim_trailing(trimmed, ",")
    else
      trimmed
    end
  end

  defp leading_spaces(line) do
    case Regex.run(~r/^(\s*)/, line, capture: :first) do
      [spaces] -> String.length(spaces)
      _ -> 0
    end
  end
end
