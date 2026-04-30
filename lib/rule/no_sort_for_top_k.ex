defmodule Credence.Rule.NoSortForTopK do
  @moduledoc """
  Detects inefficient patterns where a full sort is performed only to
  retrieve a small number of elements (top-k).

  ## Flagged patterns

  | Pattern                                    | Suggested replacement           |
  | ------------------------------------------ | ------------------------------- |
  | `Enum.sort/1 \|> Enum.take(1)`             | `Enum.max/1` — O(n)            |
  | `Enum.sort/1 \|> Enum.take(k)`             | `Enum.reduce/3` (track top k)  |
  | `Enum.sort/1 \|> hd/1`                     | `Enum.max/1`                   |
  | `Enum.sort/1 \|> Enum.at(0)`               | `Enum.min/1`                   |
  | `Enum.sort/1 \|> Enum.at(1)`               | `Enum.reduce/3` (top two)      |
  | `Enum.sort/1 \|> Enum.reverse/1 \|> …`     | Same as above (reverse skipped)|

  Sorting an entire collection is O(n log n). When only the first or last
  few elements are needed, a single-pass O(n) approach is both faster and
  clearer in intent.

  ## Severity

  `:warning`
  """

  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case extract_pipeline(node) do
          {:ok, var, op, k, meta} ->
            issue = %Issue{
              rule: :no_sort_for_top_k,
              severity: :warning,
              message: build_message(op, var, k),
              meta: %{line: Keyword.get(meta, :line)}
            }

            {node, [issue | issues]}

          :error ->
            {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  # ------------------------------------------------------------
  # PIPELINE NORMALIZATION
  # ------------------------------------------------------------

  defp extract_pipeline({:|>, meta, _} = node) do
    pipeline = flatten_pipeline(node)

    case analyze_pipeline(pipeline) do
      {:ok, var, op, k} -> {:ok, var, op, k, meta}
      :error -> :error
    end
  end

  defp extract_pipeline(_), do: :error

  defp flatten_pipeline({:|>, _, [left, right]}) do
    flatten_pipeline(left) ++ [right]
  end

  defp flatten_pipeline(expr), do: [expr]

  # ------------------------------------------------------------
  # ANALYSIS
  # ------------------------------------------------------------

  defp analyze_pipeline([first | rest]) do
    with {:ok, var} <- extract_sort(first),
         {:ok, op, k} <- find_topk(rest) do
      {:ok, var, op, k}
    else
      _ -> :error
    end
  end

  # ------------------------------------------------------------
  # SORT DETECTION
  # ------------------------------------------------------------

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

  # ------------------------------------------------------------
  # TOP-K DETECTION
  #
  # In a flattened pipeline the right-hand steps carry only their
  # *explicit* arguments — the piped value is implicit and absent
  # from the AST.  For example `Enum.take(3)` has args `[3]`, not
  # `[piped, 3]`.  Each clause therefore matches the pipeline
  # (single-arg) form.
  # ------------------------------------------------------------

  defp find_topk([]), do: :error

  defp find_topk([expr | rest]) do
    case extract_topk(expr) do
      {:ok, _op, _k} = result -> result
      :reverse -> find_topk(rest)
      _ -> :error
    end
  end

  # Pipeline form: the piped collection is implicit, only `k` is present.
  defp extract_topk({{:., _, [mod, :take]}, _, [k]}) do
    if enum_module?(mod) and is_integer(k), do: {:ok, :take, k}, else: :error
  end

  # Pipeline form: only the index is present.
  defp extract_topk({{:., _, [mod, :at]}, _, [idx]}) do
    if enum_module?(mod) and is_integer(idx) and idx in [0, 1],
      do: {:ok, :at, idx},
      else: :error
  end

  # Pipeline form: hd() receives its argument via the pipe, so args is [].
  defp extract_topk({:hd, _, []}), do: {:ok, :hd, 1}

  # Pipeline form: Enum.reverse() — no explicit args.
  defp extract_topk({{:., _, [mod, :reverse]}, _, []}) do
    if enum_module?(mod), do: :reverse, else: :error
  end

  defp extract_topk(_), do: :error

  # ------------------------------------------------------------
  # MESSAGE GENERATION
  # ------------------------------------------------------------

  defp build_message(:take, var, 1) do
    """
    Enum.sort/1 |> Enum.take(1) on `#{var}` is unnecessary O(n log n).

    Use Enum.max/1 instead for O(n):
        Enum.max(#{var})
    """
  end

  defp build_message(:take, var, k) do
    """
    Enum.sort/1 |> Enum.take(#{k}) on `#{var}` fully sorts the list (O(n log n))
    even though only top #{k} elements are needed.

    Better options:
    • Enum.reduce/3 (track top #{k})
    • Min-heap approach for large datasets
    """
  end

  defp build_message(:hd, var, _) do
    """
    Enum.sort/1 |> hd/1 on `#{var}` is inefficient.

    Use Enum.max/1 instead.
    """
  end

  defp build_message(:at, var, 0) do
    """
    Enum.sort/1 |> Enum.at(0) on `#{var}` is unnecessary sorting.

    Use Enum.min/1 instead.
    """
  end

  defp build_message(:at, var, 1) do
    """
    Enum.sort/1 |> Enum.at(1) on `#{var}` is inefficient.

    Consider Enum.reduce/3 to track top two values in one pass.
    """
  end

  # ------------------------------------------------------------
  # HELPERS
  # ------------------------------------------------------------

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?(_), do: false

  defp var_name({name, _, context}) when is_atom(name) and is_atom(context), do: name
  defp var_name(_), do: nil
end
