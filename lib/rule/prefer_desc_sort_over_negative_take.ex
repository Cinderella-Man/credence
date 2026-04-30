defmodule Credence.Rule.PreferDescSortOverNegativeTake do
  @moduledoc """
  Prefer `Enum.sort(nums, :desc) |> Enum.take(n)`
  over `Enum.sort(nums) |> Enum.take(-n)`.

  This is about readability and intent clarity, not performance.
  """

  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:|>, meta, _} = node, acc ->
          pipeline = flatten_pipeline(node)

          if match_pattern?(pipeline) do
            {node, [build_issue(meta) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  # -------------------------
  # Pipeline handling
  # -------------------------

  defp flatten_pipeline({:|>, _, [left, right]}) do
    flatten_pipeline(left) ++ [right]
  end

  defp flatten_pipeline(other), do: [other]

  # -------------------------
  # Pattern detection
  # -------------------------

  defp match_pattern?(pipeline) do
    has_plain_sort?(pipeline) and has_negative_take?(pipeline)
  end

  defp has_plain_sort?(pipeline) do
    Enum.any?(pipeline, fn
      {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, args} ->
        args == []

      _ ->
        false
    end)
  end

  defp has_negative_take?(pipeline) do
    Enum.any?(pipeline, fn
      {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, _, [n]} ->
        is_negative_integer(n)

      _ ->
        false
    end)
  end

  # -------------------------
  # Helpers
  # -------------------------

  defp is_negative_integer({:-, _, [int]}) when is_integer(int), do: true
  defp is_negative_integer(int) when is_integer(int) and int < 0, do: true
  defp is_negative_integer(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_desc_sort_over_negative_take,
      severity: :refactor,
      message: """
      Prefer `Enum.sort(nums, :desc) |> Enum.take(3)`
      over `Enum.sort(nums) |> Enum.take(-3)`.

      This is about readability and intent clarity, not performance.
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
