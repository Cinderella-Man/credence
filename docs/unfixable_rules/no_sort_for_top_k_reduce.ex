defmodule Credence.Pattern.NoSortForTopKReduce do
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
  | `Enum.sort/1 \\|> Enum.take(k)` for k > 1  | `Enum.reduce/3` (track top k)  |
  | `Enum.sort/1 \\|> Enum.at(1)`               | `Enum.reduce/3` (track top two)|
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

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: false

  @impl true
  def check(ast, _opts) do
    collect_issues(ast, []) |> Enum.reverse()
  end

  # ── Custom AST traversal ─────────────────────────────────────────
  #
  # We avoid Macro.prewalk because it visits inner |> sub-expressions
  # independently.  For `sort |> take(2) |> length()`, prewalk would
  # also visit the inner `sort |> take(2)` node and incorrectly flag
  # it.  Instead, when we encounter a |> node we flatten the entire
  # pipeline, analyse it once, then recurse only into each step's
  # *arguments* — never back into the pipe structure.

  # Pipeline node — flatten, analyse, then recurse into step args only.
  defp collect_issues({:|>, meta, _} = node, issues) do
    pipeline = flatten_pipeline(node)

    issues =
      case analyze_pipeline(pipeline) do
        {:ok, var, op, k, reverses} ->
          issue = %Issue{
            rule: :no_sort_for_top_k_reduce,
            message: build_message(op, var, k, reverses),
            meta: %{line: Keyword.get(meta, :line)}
          }

          [issue | issues]

        :error ->
          issues
      end

    # Recurse into each pipeline step's arguments, NOT into the pipe structure
    Enum.reduce(pipeline, issues, fn step, acc ->
      step |> step_args() |> Enum.reduce(acc, fn arg, a -> collect_issues(arg, a) end)
    end)
  end

  # Regular 3-tuple AST node (calls, blocks, etc.)
  defp collect_issues({_form, _meta, args}, issues) when is_list(args) do
    Enum.reduce(args, issues, fn arg, acc -> collect_issues(arg, acc) end)
  end

  # 2-tuple — keyword list entries like {:do, body}, {:else, body}
  defp collect_issues({key, value}, issues) when is_atom(key) do
    collect_issues(value, issues)
  end

  # Lists — argument lists, block bodies, keyword lists
  defp collect_issues(list, issues) when is_list(list) do
    Enum.reduce(list, issues, fn item, acc -> collect_issues(item, acc) end)
  end

  # Leaf nodes (atoms, numbers, strings, etc.)
  defp collect_issues(_leaf, issues), do: issues

  # Extract the user-visible arguments from a single pipeline step.
  defp step_args({{:., _, _}, _, args}) when is_list(args), do: args
  defp step_args({_name, _, args}) when is_list(args), do: args
  defp step_args(_), do: []

  # ── Pipeline helpers ─────────────────────────────────────────────

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
