defmodule Credence.Rule.NoMultiplyByOnePointZero do
  @moduledoc """
  Detects `expr * 1.0` used to coerce an integer result to a float.

  This is a Python idiom (`int * 1.0` produces a float) that LLMs carry
  over to Elixir. In Elixir, `* 1.0` is a no-op — it does not change the
  runtime type the way it does in Python. If a float result is needed,
  Elixir's `/` operator always returns a float naturally.

  ## Bad

      Enum.at(sorted_list, mid) * 1.0

      count * 1.0

      count = count * 1.0

  ## Good

      Enum.at(sorted_list, mid)

      count

      # (self-assignment line removed entirely)

  ## Auto-fix

  Removes the `* 1.0` (or `1.0 *`) from the expression. When the entire
  line is a no-op self-assignment (`var = var * 1.0`), the line is deleted.
  """

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # expr * 1.0
        {:*, meta, [_expr, val]} = node, acc when is_float(val) and val == 1.0 ->
          {node, [build_issue(meta) | acc]}

        # 1.0 * expr
        {:*, meta, [val, _expr]} = node, acc when is_float(val) and val == 1.0 ->
          {node, [build_issue(meta) | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        target_lines = find_target_lines(ast)

        if target_lines == [] do
          source
        else
          line_set = MapSet.new(target_lines)

          source
          |> String.split("\n")
          |> Enum.with_index(1)
          |> Enum.flat_map(fn {line, idx} ->
            if idx in line_set do
              case fix_line(line) do
                :delete -> []
                fixed -> [fixed]
              end
            else
              [line]
            end
          end)
          |> Enum.join("\n")
        end

      {:error, _} ->
        source
    end
  end

  defp find_target_lines(ast) do
    {_ast, lines} =
      Macro.prewalk(ast, [], fn
        {:*, meta, [_expr, val]} = node, acc when is_float(val) and val == 1.0 ->
          {node, [Keyword.get(meta, :line) | acc]}

        {:*, meta, [val, _expr]} = node, acc when is_float(val) and val == 1.0 ->
          {node, [Keyword.get(meta, :line) | acc]}

        # Sourceror wraps floats in __block__
        {:*, meta, [_expr, {:__block__, _, [val]}]} = node, acc
        when is_float(val) and val == 1.0 ->
          {node, [Keyword.get(meta, :line) | acc]}

        {:*, meta, [{:__block__, _, [val]}, _expr]} = node, acc
        when is_float(val) and val == 1.0 ->
          {node, [Keyword.get(meta, :line) | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(lines)
  end

  defp fix_line(line) do
    cond do
      # Self-assignment: var = var * 1.0 → delete entire line
      Regex.match?(~r/^\s*(\w+)\s*=\s*\1\s*\*\s*1\.0(?![0-9eE_])\s*$/, line) ->
        :delete

      # Self-assignment: var = 1.0 * var → delete entire line
      Regex.match?(~r/^\s*(\w+)\s*=\s*1\.0\s*\*\s*\1\s*$/, line) ->
        :delete

      true ->
        line
        # Remove trailing * 1.0
        |> then(&Regex.replace(~r/\s*\*\s*1\.0(?![0-9eE_])/, &1, ""))
        # Remove leading 1.0 *
        |> then(&Regex.replace(~r/1\.0\s*\*\s*/, &1, ""))
    end
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_multiply_by_one_point_zero,
      message: """
      `* 1.0` to convert an integer to a float is a Python idiom that \
      has no effect in Elixir. Remove it.
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
