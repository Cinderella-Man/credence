defmodule Credence.Rule.PreferDescSortOverNegativeTake do
  @moduledoc """
  Prefer `Enum.sort(nums, :desc) |> Enum.take(n)`
  over `Enum.sort(nums) |> Enum.take(-n)`.
  This is about readability and intent clarity, not performance.

  ## Bad

      nums
      |> Enum.sort()
      |> Enum.take(-3)

  ## Good

      nums
      |> Enum.sort(:desc)
      |> Enum.take(3)
  """
  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

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

  @impl true
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.prewalk(fn
      {:|>, _, _} = node ->
        pipeline = flatten_pipeline(node)

        if match_pattern?(pipeline) and adjacent_sort_take?(pipeline) do
          transform_pipeline(node)
        else
          node
        end

      node ->
        node
    end)
    |> Sourceror.to_string()
  end

  # ── Fix helpers ──────────────────────────────────────────────────

  defp transform_pipeline({:|>, meta, [left, right]}) do
    {:|>, meta, [transform_pipeline(left), transform_step(right)]}
  end

  defp transform_pipeline(node), do: transform_step(node)

  # Enum.sort() → Enum.sort(:desc)
  defp transform_step({{:., dm, [{:__aliases__, am, [:Enum]}, :sort]}, cm, []}) do
    {{:., dm, [{:__aliases__, am, [:Enum]}, :sort]}, cm, [wrap_literal(:desc)]}
  end

  # Enum.take(-n) → Enum.take(n)
  defp transform_step({{:., dm, [{:__aliases__, am, [:Enum]}, :take]}, cm, [n]}) do
    case positive_value(n) do
      {:ok, pos} ->
        {{:., dm, [{:__aliases__, am, [:Enum]}, :take]}, cm, [wrap_literal(pos)]}

      :error ->
        {{:., dm, [{:__aliases__, am, [:Enum]}, :take]}, cm, [n]}
    end
  end

  defp transform_step(node), do: node

  # ── Literal wrapping ───────────────────────────────────────────
  # Sourceror.to_string/1 → Code.Formatter requires __block__ nodes
  # to carry a :token key in their metadata so the formatter knows
  # how to render the literal.

  defp wrap_literal(atom) when is_atom(atom),
    do: {:__block__, [token: inspect(atom)], [atom]}

  defp wrap_literal(int) when is_integer(int),
    do: {:__block__, [token: Integer.to_string(int)], [int]}

  # ── Integer extraction (handles Sourceror's __block__ wrapper) ──

  defp positive_value({:-, _, [int]}) when is_integer(int), do: {:ok, int}

  defp positive_value({:-, _, [{:__block__, _, [int]}]}) when is_integer(int),
    do: {:ok, int}

  defp positive_value({:__block__, _, [int]}), do: positive_value(int)
  defp positive_value(int) when is_integer(int) and int < 0, do: {:ok, abs(int)}
  defp positive_value(int) when is_integer(int), do: {:ok, int}
  defp positive_value(_), do: :error

  # ── Adjacency guard ─────────────────────────────────────────────

  defp adjacent_sort_take?(pipeline) do
    pipeline
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn
      [s, t] -> plain_sort?(s) and negative_take?(t)
      _ -> false
    end)
  end

  defp plain_sort?({{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, args}), do: args == []
  defp plain_sort?(_), do: false

  defp negative_take?({{:., _, [{:__aliases__, _, [:Enum]}, :take]}, _, [n]}),
    do: negative_integer?(n)

  defp negative_take?(_), do: false

  # ── Shared pipeline helpers ─────────────────────────────────────

  defp flatten_pipeline({:|>, _, [left, right]}) do
    flatten_pipeline(left) ++ [right]
  end

  defp flatten_pipeline(other), do: [other]

  defp match_pattern?(pipeline) do
    has_plain_sort?(pipeline) and has_negative_take?(pipeline)
  end

  defp has_plain_sort?(pipeline) do
    Enum.any?(pipeline, fn
      {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, args} -> args == []
      _ -> false
    end)
  end

  defp has_negative_take?(pipeline) do
    Enum.any?(pipeline, fn
      {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, _, [n]} -> negative_integer?(n)
      _ -> false
    end)
  end

  defp negative_integer?({:-, _, [int]}) when is_integer(int), do: true

  defp negative_integer?({:-, _, [{:__block__, _, [int]}]}) when is_integer(int),
    do: true

  defp negative_integer?({:__block__, _, [int]}), do: negative_integer?(int)
  defp negative_integer?(int) when is_integer(int) and int < 0, do: true
  defp negative_integer?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_desc_sort_over_negative_take,
      message: """
      Prefer `Enum.sort(nums, :desc) |> Enum.take(3)`
      over `Enum.sort(nums) |> Enum.take(-3)`.
      This is about readability and intent clarity, not performance.
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
