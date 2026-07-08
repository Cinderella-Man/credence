defmodule Credence.Syntax.NoAfterOrRescueInCase do
  @moduledoc """
  Detects and repairs `case` blocks that misuse `after` or `rescue`.

  LLMs confuse `case` and `try` syntax, writing `case … after … rescue … end`
  which compiles to "unexpected option :after in case". The deterministic fix
  wraps the `case` in a `try` block and moves the `after`/`rescue` clauses
  out of the `case` options and into the `try`.

  ## Bad (compiles with error)

      case Map.get(%{}, :key) do
        nil -> :not_found
        value -> {:ok, value}
      after
        :cleanup
      rescue
        _ -> :error
      end

  ## Good

      try do
        case Map.get(%{}, :key) do
          nil -> :not_found
          value -> {:ok, value}
        end
      after
        :cleanup
      rescue
        _ -> :error
      end
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @impl true
  def analyze(source) do
    case find_case_with_after_or_rescue(source) do
      {:ok, case_line, _first_option_line, _option_keys} ->
        [
          %Issue{
            rule: :no_after_or_rescue_in_case,
            message: "`after`/`rescue` inside `case` — wrap in `try` instead",
            meta: %{line: case_line}
          }
        ]

      :none ->
        []
    end
  end

  @impl true
  def fix(source) do
    case find_case_with_after_or_rescue(source) do
      {:ok, case_line, first_option_line, _option_keys} ->
        fixed = apply_fix(source, case_line, first_option_line)
        if fixed == source, do: source, else: fix(fixed)

      :none ->
        source
    end
  end

  # Parse with Sourceror and walk the AST to find a `case` node whose keyword
  # options include `:after` or `:rescue`. Returns
  # `{:ok, case_line, first_option_line, option_keys}` or `:none`.
  defp find_case_with_after_or_rescue(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {_ast, result} =
          Macro.prewalk(ast, nil, fn
            {:case, meta, [_subject, opts]} = node, nil when is_list(opts) ->
              bad_opts =
                Enum.filter(opts, fn
                  {{:__block__, _, [key]}, _} when key in [:after, :rescue] -> true
                  _ -> false
                end)

              case bad_opts do
                [] ->
                  {node, nil}

                _ ->
                  first = Enum.min_by(bad_opts, fn {{:__block__, m, _}, _} -> m[:line] end)
                  {{:__block__, first_meta, _}, _} = first
                  opt_keys = Enum.map(bad_opts, fn {{:__block__, _, [k]}, _} -> k end)
                  {node, {:ok, meta[:line], first_meta[:line], opt_keys}}
              end

            node, acc ->
              {node, acc}
          end)

        result || :none

      _ ->
        :none
    end
  end

  # Source surgery: wrap the case in `try do ... end` and move after/rescue out.
  #
  # 1. Insert `try do` before the case line (same indent).
  # 2. Indent case body (lines between case and first option) by 2 extra spaces.
  # 3. Insert `end` before the first option line (closes the case).
  # 4. Keep after/rescue + their bodies at original indent.
  # 5. The existing `end` (after rescue body) now closes the `try`.
  defp apply_fix(source, case_line, first_option_line) do
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

          idx > case_line and idx < first_option_line ->
            if trimmed == "", do: [line], else: ["  " <> line]

          idx == first_option_line ->
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
