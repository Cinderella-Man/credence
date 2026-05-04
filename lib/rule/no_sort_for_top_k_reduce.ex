defmodule Credence.Rule.NoSortForTopKReduce do
  @moduledoc """
  Detects inefficient patterns where a full sort is performed only to
  retrieve a small number of elements (top-k) that cannot be reduced to
  a single `Enum.min/1` or `Enum.max/1` call.

  Sorting an entire collection is O(n log n). When only a few elements
  are needed, a single-pass O(n) approach using `Enum.reduce/3` is
  both faster and clearer in intent.

  ## Flagged patterns

  | Pattern                                    | Suggested replacement           |
  | ------------------------------------------ | ------------------------------- |
  | `Enum.sort/1 \|> Enum.take(k)` for k > 1  | `Enum.reduce/3` (track top k)  |
  | `Enum.sort/1 \|> Enum.at(1)`               | `Enum.reduce/3` (track top two)|
  | (same patterns with `Enum.reverse()` before the terminal step) ||

  These patterns are **not automatically fixable** because the correct
  replacement depends on the desired sort direction and requires a
  multi-step `Enum.reduce/3` or min-heap approach.

  ## Bad

      Enum.sort(list) |> Enum.take(5)
      Enum.sort(list) |> Enum.at(1)

  ## Good

      # Use Enum.reduce/3 to track the top-k elements in one pass
  """

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: false

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case extract_pipeline(node) do
          {:ok, var, op, k, reverses, meta} ->
            issue = %Issue{
              rule: :no_sort_for_top_k_reduce,
              message: build_message(op, var, k, reverses),
              meta: %{line: Keyword.get(meta, :line)}
            }
            {node, [issue | issues]}

          :error ->
            {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  # ── Check helpers ────────────────────────────────────────────────

  defp extract_pipeline({:|>, meta, _} = node) do
    pipeline = flatten_pipeline(node)

    case analyze_pipeline(pipeline) do
      {:ok, var, op, k, reverses} -> {:ok, var, op, k, reverses, meta}
      :error -> :error
    end
  end

  defp extract_pipeline(_), do: :error

  defp flatten_pipeline({:|>, _, [left, right]}) do
    flatten_pipeline(left) ++ [right]
  end

  defp flatten_pipeline(expr), do: [expr]

  defp analyze_pipeline([first | rest]) do
    with {:ok, var} <- extract_sort(first),
         {:ok, op, k, reverses} <- find_topk(rest) do
      {:ok, var, op, k, reverses}
    end
  end

  defp extract_sort({{:., _, [mod, :sort]}, _, [arg | _]}) do
    if enum_module?(mod) do
      case var_name(arg) do
        nil -> :error
        var -> {:ok, var}
      end
    else
      :error
    end
  end

  defp extract_sort(_), do: :error

  # Requires the terminal operation to be the LAST step in the
  # pipeline.  Intermediate steps must all be Enum.reverse().
  defp find_topk(exprs), do: do_find_topk(exprs, 0)

  defp do_find_topk([], _reverses), do: :error

  defp do_find_topk([expr], reverses) do
    case extract_topk(expr) do
      {:ok, op, k} -> {:ok, op, k, reverses}
      _ -> :error
    end
  end

  defp do_find_topk([expr | rest], reverses) do
    case extract_topk(expr) do
      :reverse -> do_find_topk(rest, reverses + 1)
      _ -> :error
    end
  end

  # Only match the multi-element / complex terminals.
  defp extract_topk({{:., _, [mod, :take]}, _, [k]}) when is_integer(k) and k > 1 do
    if enum_module?(mod), do: {:ok, :take, k}, else: :error
  end

  defp extract_topk({{:., _, [mod, :at]}, _, [1]}) do
    if enum_module?(mod), do: {:ok, :at, 1}, else: :error
  end

  defp extract_topk({{:., _, [mod, :reverse]}, _, []}) do
    if enum_module?(mod), do: :reverse, else: :error
  end

  defp extract_topk(_), do: :error

  defp build_message(op, var, k, reverses) do
    is_reversed = rem(reverses, 2) == 1

    case op do
      :take ->
        direction = if is_reversed, do: "largest", else: "smallest"

        """
        Enum.sort/1 |> Enum.take(#{k}) on `#{var}` fully sorts the list (O(n log n)) \
        even though only the #{k} #{direction} elements are needed.
        Better options:
        • Enum.reduce/3 (track top #{k})
        • Min-heap approach for large datasets
        """

      :at ->
        direction = if is_reversed, do: "largest", else: "smallest"

        """
        Enum.sort/1 |> Enum.at(1) on `#{var}` is inefficient.
        Consider Enum.reduce/3 to track the top two #{direction} values in one pass.
        """
    end
  end

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?(_), do: false

  defp var_name({name, _, context}) when is_atom(name) and is_atom(context), do: name
  defp var_name(_), do: nil
end
