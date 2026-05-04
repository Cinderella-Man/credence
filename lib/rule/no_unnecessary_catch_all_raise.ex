defmodule Credence.Rule.NoUnnecessaryCatchAllRaise do
  @moduledoc """
  Detects function clauses where every argument is a wildcard and the
  body does nothing but `raise`.

  ## Why this matters

  Elixir's `FunctionClauseError` is a first-class debugging tool.  When
  no clause matches, the runtime raises an error that names the function
  _and_ shows the exact arguments that failed to match.  A hand-written
  catch-all that raises a generic error actively degrades that signal:

      # Bad — hides the actual arguments from the error
      def missing_number(_), do: raise(ArgumentError, "expected a list")

      # Good — Elixir does this automatically, with better diagnostics
      # (just remove the catch-all clause entirely)

  LLMs generate these defensive catch-alls frequently because their
  training data includes Python / Java patterns where unhandled cases
  must be raised explicitly.  In Elixir the convention is to let
  non-matching calls crash naturally.

  ## Flagged patterns

  Any `def` / `defp` clause where:
  1. **Every** argument is a wildcard `_` or `_name`), and
  2. The body consists solely of a `raise` call.

  Guarded clauses are not flagged — the guard implies intentional
  matching logic even if the arguments are wildcards.

  ## Not flagged

  - Catch-all clauses that return a value (e.g. `{:error, :invalid}`)
  - Clauses with logic before the raise (logging, cleanup)
  - Zero-arity functions
  - Clauses with guard expressions

  ## Fix

  Removes the unnecessary catch-all clause, letting Elixir's built-in
  `FunctionClauseError` handle unmatched arguments with better diagnostics.
  """
  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case check_node(node) do
          {:ok, issue} -> {node, [issue | issues]}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    {:ok, ast} = Code.string_to_quoted(source)

    to_remove = collect_removal_targets(ast)

    case MapSet.size(to_remove) do
      0 ->
        source

      _ ->
        ranges = find_removal_ranges(source, to_remove)

        result =
          ranges
          |> Enum.sort_by(fn {s, _} -> -s end)
          |> Enum.reduce(source, fn {start_pos, end_pos}, src ->
            before = binary_part(src, 0, start_pos)
            after_part = binary_part(src, end_pos, byte_size(src) - end_pos)
            before <> after_part
          end)
          |> String.replace(~r/\n{3,}/, "\n\n")
          |> String.trim_trailing("\n")

        result <> "\n"
    end
  end

  # ------------------------------------------------------------
  # FIX: IDENTIFY CATCH-ALL-RAISES
  #
  # Walks the AST (using the same parser as check) and collects
  # {name, arity, line} triples so we match the exact clause,
  # not every clause with the same name/arity.
  # ------------------------------------------------------------

  defp collect_removal_targets(ast) do
    {_ast, targets} =
      Macro.prewalk(ast, [], fn node, acc ->
        case node do
          {def_type, meta, [{fn_name, _, args}, body]}
          when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) ->
            if all_wildcards?(args) and body_only_raises?(body) do
              line = Keyword.get(meta, :line)
              {node, [{fn_name, length(args), line} | acc]}
            else
              {node, acc}
            end

          _ ->
            {node, acc}
        end
      end)

    MapSet.new(targets)
  end

  # ------------------------------------------------------------
  # FIX: TEXT-BASED REMOVAL
  #
  # Scans source text to find byte ranges of flagged function
  # definitions.  Uses line numbers from the AST to match the
  # exact clause, avoiding false matches on other clauses of
  # the same function.
  # ------------------------------------------------------------

  defp find_removal_ranges(source, targets) do
    lines = String.split(source, "\n")

    targets
    |> Enum.flat_map(fn {name, _arity, line} ->
      # AST lines are 1-indexed; our list is 0-indexed
      idx = line - 1

      case Enum.at(lines, idx) do
        nil ->
          []

        text ->
          if Regex.match?(~r/^\s*(defp?)\s+/, text) do
            case find_function_range(lines, idx, name) do
              {:ok, range} -> [range]
              :error -> []
            end
          else
            []
          end
      end
    end)
  end

  defp find_function_range(lines, start_idx, name) do
    first_line = Enum.at(lines, start_idx)

    # Keyword-style: entire def on one line with `do:` before any bare `do`
    if Regex.match?(~r/\bdo\s*:/, first_line) and
         Regex.match?(~r/^(\s*)(defp?)\s+#{name}\s*\(/, first_line) do
      {:ok, line_range_to_byte_range(lines, start_idx, start_idx)}
    else
      # Do-block style: find the matching `end` by tracking nesting
      case find_matching_end(lines, start_idx) do
        {:ok, end_idx} ->
          {:ok, line_range_to_byte_range(lines, start_idx, end_idx)}

        :error ->
          :error
      end
    end
  end

  defp find_matching_end(lines, def_line_idx) do
    case find_do_keyword(lines, def_line_idx) do
      {:ok, do_line_idx} ->
        scan_for_end(lines, do_line_idx + 1, 1)

      :error ->
        :error
    end
  end

  defp find_do_keyword(lines, start_idx) do
    lines
    |> Enum.drop(start_idx)
    |> Enum.with_index(start_idx)
    |> Enum.find_value(:error, fn {line, idx} ->
      if Regex.match?(~r/\bdo\s*$/, line), do: {:ok, idx}
    end)
  end

  defp scan_for_end(lines, start_idx, initial_depth) do
    lines
    |> Enum.drop(start_idx)
    |> Enum.with_index(start_idx)
    |> Enum.reduce_while(initial_depth, fn {line, idx}, depth ->
      trimmed = String.trim(line)

      cond do
        Regex.match?(~r/^end\b/, trimmed) ->
          new_depth = depth - 1

          if new_depth == 0 do
            {:halt, {:found, idx}}
          else
            {:cont, new_depth}
          end

        Regex.match?(~r/\bdo\s*$/, line) ->
          {:cont, depth + 1}

        true ->
          {:cont, depth}
      end
    end)
    |> case do
      {:found, idx} -> {:ok, idx}
      _ -> :error
    end
  end

  defp line_range_to_byte_range(lines, start_line, end_line) do
    before =
      lines
      |> Enum.take(start_line)
      |> Enum.join("\n")

    start_byte =
      case start_line do
        0 -> 0
        _ -> byte_size(before) + 1
      end

    range_text =
      lines
      |> Enum.slice(start_line..end_line)
      |> Enum.join("\n")

    {start_byte, start_byte + byte_size(range_text)}
  end

  # ------------------------------------------------------------
  # NODE MATCHING
  # ------------------------------------------------------------

  defp check_node({def_type, meta, [{fn_name, _, args}, body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    if all_wildcards?(args) and body_only_raises?(body) do
      {:ok,
       %Issue{
         rule: :no_unnecessary_catch_all_raise,
         message: build_message(def_type, fn_name, length(args)),
         meta: %{line: Keyword.get(meta, :line)}
       }}
    else
      :error
    end
  end

  defp check_node(_), do: :error

  # A zero-arity function cannot be a "catch-all".
  defp all_wildcards?([]), do: false
  defp all_wildcards?(args), do: Enum.all?(args, &wildcard?/1)

  defp wildcard?({:_, _, ctx}) when is_atom(ctx), do: true

  defp wildcard?({name, _, ctx}) when is_atom(name) and is_atom(ctx) do
    name |> Atom.to_string() |> String.starts_with?("_")
  end

  defp wildcard?(_), do: false

  defp body_only_raises?(do: {:raise, _, _}), do: true
  defp body_only_raises?(_), do: false

  defp build_message(def_type, fn_name, arity) do
    """
    Unnecessary catch-all clause in `#{def_type} #{fn_name}/#{arity}`.
    This clause matches all remaining arguments only to raise an error.
    Elixir already raises a `FunctionClauseError` when no clause matches,
    and it includes the actual failing arguments in the error — which is
    more useful for debugging than a generic message.
    Remove this clause and let Elixir's built-in error handling do the work.
    """
  end
end
