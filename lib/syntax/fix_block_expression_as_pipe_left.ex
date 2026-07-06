defmodule Credence.Syntax.FixBlockExpressionAsPipeLeft do
  @moduledoc """
  Fixes block expressions (if/case/cond) piped into non-callable targets
  containing capture variables (`&1`).

  LLMs sometimes pipe a block expression into a tuple literal with a capture
  variable, e.g. `if ... end |> {state, &1}`. This parses but is a compile
  error — you can only pipe into local calls, remote calls, or anonymous
  function calls.

  The fix extracts the block result into a local binding and replaces the
  capture variable with the binding:

      # Before
      if true do
        {:ok, 42}
      end
      |> {state, &1}

      # After
      if_result =
        if true do
          {:ok, 42}
        end

      {state, if_result}
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if problematic_pipe_line?(line) do
        [
          %Issue{
            rule: :fix_block_expression_as_pipe_left,
            message:
              "Cannot pipe a block expression into a non-callable target with capture variables. " <>
                "Extract the block result into a local binding instead.",
            meta: %{line: line_no}
          }
        ]
      else
        []
      end
    end)
  end

  @impl true
  def fix(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        patches = collect_pipe_patches(ast, source)

        case patches do
          [] -> source
          _ -> apply_patches(source, patches)
        end

      {:error, _} ->
        source
    end
  end

  # Collect patches for pipe expressions where RHS is a non-callable with &N
  defp collect_pipe_patches(ast, source) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn
        {:|>, _pipe_meta, [left, right]} = node, acc ->
          if contains_capture?(right) and not callable_rhs?(right) do
            case build_pipe_patch(left, right, source) do
              {:ok, patch} -> {node, [patch | acc]}
              :error -> {node, acc}
            end
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    patches
  end

  # Check if an AST node contains &N capture references
  defp contains_capture?({:&, _, [n]}) when is_integer(n), do: true
  defp contains_capture?({_, _, args}) when is_list(args) do
    Enum.any?(args, &contains_capture?/1)
  end
  defp contains_capture?({a, b}), do: contains_capture?(a) or contains_capture?(b)
  defp contains_capture?(_), do: false

  # Check if RHS is a callable target (function call).
  # Sourceror wraps tuple literals as {:__block__, [closing: ...], [elements]},
  # so we must NOT treat __block__ as callable.
  defp callable_rhs?({{:., _, _}, _, args}) when is_list(args), do: true
  defp callable_rhs?({name, meta, args}) when is_atom(name) and is_list(args) do
    name != :__block__ and not Keyword.has_key?(meta || [], :closing)
  end
  defp callable_rhs?(_), do: false

  defp build_pipe_patch(left, right, source) do
    left_range = Sourceror.get_range(left)
    right_range = Sourceror.get_range(right)

    case {left_range, right_range} do
      {%Sourceror.Range{} = lr, %Sourceror.Range{} = rr} ->
        block_type = detect_block_type(left)
        var_name = "#{block_type}_result"
        indent_col = lr.start[:column]

        left_start = range_to_offset(lr.start, source)
        left_end = range_to_offset(lr.end, source)
        right_start = range_to_offset(rr.start, source)
        right_end = range_to_offset(rr.end, source)

        block_text = String.slice(source, left_start, left_end - left_start)
        rhs_text = String.slice(source, right_start, right_end - right_start)
        fixed_rhs = Regex.replace(~r/&\d+/, rhs_text, var_name)

        # The replacement starts at the block start. The `before` text (from
        # String.slice(source, 0, left_start)) already includes the line
        # indentation. So the replacement must NOT re-add that indent.
        replacement = build_replacement(var_name, block_text, fixed_rhs, indent_col)

        {:ok, %{start: left_start, end: right_end, replacement: replacement}}

      _ ->
        :error
    end
  end

  # Build replacement text. The `before` text (source up to left_start)
  # already includes the line's leading indentation. The first line of the
  # replacement therefore starts directly with "var_name =" (no leading
  # spaces). All subsequent lines carry their own absolute indentation.
  defp build_replacement(var_name, block_text, fixed_rhs, indent_col) do
    [first | rest] = String.split(block_text, "\n")
    first_content = String.trim_leading(first)
    num_rest = length(rest)

    indented_rest =
      rest
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {line, idx} ->
        cond do
          # Last line (end keyword): align with if keyword at indent_col + 2
          idx == num_rest - 1 ->
            spaces(indent_col + 1) <> String.trim_leading(line)

          # Body lines: shift their original indent by +2
          String.trim(line) != "" ->
            extra = String.length(line) - String.length(String.trim_leading(line))
            spaces(extra + 2) <> String.trim_leading(line)

          true ->
            ""
        end
      end)

    rhs_line = spaces(indent_col - 1) <> fixed_rhs
    "#{var_name} =\n#{spaces(indent_col + 1)}#{first_content}\n#{indented_rest}\n\n#{rhs_line}"
  end

  defp spaces(n), do: String.duplicate(" ", max(n, 0))

  defp detect_block_type({:if, _, _}), do: "if"
  defp detect_block_type({:case, _, _}), do: "case"
  defp detect_block_type({:cond, _, _}), do: "cond"
  defp detect_block_type({:with, _, _}), do: "with"
  defp detect_block_type(_), do: "block"

  # Convert a Sourceror position [line: N, column: M] to 0-based byte offset.
  # Columns are 1-based in Sourceror metadata.
  defp range_to_offset([line: line, column: col], source) do
    source
    |> String.split("\n")
    |> Enum.take(line - 1)
    |> Enum.map(&(byte_size(&1) + 1))
    |> Enum.sum()
    |> Kernel.+(col - 1)
  end

  # Check if a source line has a pipe into a capture-containing non-callable
  defp problematic_pipe_line?(line) do
    trimmed = String.trim_leading(line)
    not String.starts_with?(trimmed, "#") and
      Regex.match?(~r/\|>.*&\d/, line)
  end

  # Apply patches to source (in order, from right to left to preserve offsets)
  defp apply_patches(source, patches) do
    patches
    |> Enum.sort_by(& &1.start, :desc)
    |> Enum.reduce(source, fn patch, acc ->
      before = String.slice(acc, 0, patch.start)
      after_ = String.slice(acc, patch.end..-1//1)
      before <> patch.replacement <> after_
    end)
  end
end
