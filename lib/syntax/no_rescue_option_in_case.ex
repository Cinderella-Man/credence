defmodule Credence.Syntax.NoRescueOptionInCase do
  @moduledoc """
  Detects and repairs `case` blocks that misuse `rescue`.

  LLMs (especially Qwen) frequently write `case ... do ... rescue ... end`,
  confusing `case` with `try`. The parser accepts it — `rescue` appears in the
  keyword options of the `case` node — but the compiler rejects it with
  "unexpected option :rescue in case".

  The deterministic fix wraps the `case` in a `try` block and moves the
  `rescue` clause out of the `case` options and into the `try`:

  ## Bad (compiles with error)

      case File.stream!(path) do
        {:ok, stream} -> stream
        {:error, reason} -> raise reason
      rescue
        e -> {:error, e}
      end

  ## Good

      try do
        case File.stream!(path) do
          {:ok, stream} -> stream
          {:error, reason} -> raise reason
        end
      rescue
        e -> {:error, e}
      end
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @impl true
  def analyze(source) do
    case find_case_rescue(source) do
      {:ok, case_line, _rescue_line} ->
        [
          %Issue{
            rule: :no_rescue_option_in_case,
            message: "`rescue` inside `case` — wrap in `try` instead",
            meta: %{line: case_line}
          }
        ]

      :none ->
        []
    end
  end

  @impl true
  def fix(source) do
    case find_case_rescue(source) do
      {:ok, case_line, rescue_line} ->
        fixed = apply_fix(source, case_line, rescue_line)
        # There may be more case-rescue patterns; recurse until clean.
        if fixed == source, do: source, else: fix(fixed)

      :none ->
        source
    end
  end

  # Parse with Sourceror and walk the AST to find a `case` node whose keyword
  # options include `:rescue`. Returns `{:ok, case_line, rescue_line}` or `:none`.
  defp find_case_rescue(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {_ast, result} =
          Macro.prewalk(ast, nil, fn
            {:case, meta, [_subject, opts]} = node, nil when is_list(opts) ->
              case Enum.find(opts, &rescue_option?/1) do
                {{:__block__, rescue_meta, [:rescue]}, _body} ->
                  {node, {:ok, meta[:line], rescue_meta[:line]}}

                nil ->
                  {node, nil}
              end

            node, acc ->
              {node, acc}
          end)

        result || :none

      _ ->
        :none
    end
  end

  defp rescue_option?({{:__block__, _, [:rescue]}, _}), do: true
  defp rescue_option?(_), do: false

  # Source surgery: wrap the case in `try do ... end` and move rescue out.
  #
  # 1. Insert `try do` before the case line (same indent).
  # 2. Indent case body (lines between case and rescue) by 2 extra spaces.
  # 3. Insert `end` before the rescue line (closes the case).
  # 4. Keep rescue + rescue body at original indent.
  # 5. The existing `end` (after rescue body) now closes the `try`.
  defp apply_fix(source, case_line, rescue_line) do
    lines = String.split(source, "\n")
    case_indent = get_indent(Enum.at(lines, case_line - 1))
    inner_indent = case_indent <> "  "

    fixed_lines =
      lines
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, idx} ->
        trimmed = String.trim_leading(line)

        cond do
          idx == case_line ->
            ["#{case_indent}try do", "#{inner_indent}#{trimmed}"]

          idx > case_line and idx < rescue_line ->
            if trimmed == "", do: [line], else: ["  " <> line]

          idx == rescue_line ->
            ["#{inner_indent}end", "#{case_indent}#{trimmed}"]

          true ->
            [line]
        end
      end)

    Enum.join(fixed_lines, "\n")
  end

  defp get_indent(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, indent] -> indent
      _ -> ""
    end
  end
end
