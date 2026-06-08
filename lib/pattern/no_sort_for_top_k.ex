defmodule Credence.Pattern.NoSortForTopK do
  @moduledoc """
  Detects inefficient patterns where a full sort is performed only to
  retrieve the minimum or maximum element via `Enum.at(0)`.

  Sorting an entire collection is O(n log n). When only the minimum or
  maximum element is needed, `Enum.min`/`Enum.max` provides the same result
  in O(n) without allocating a sorted intermediate list. The `fn -> nil end`
  empty_fallback preserves `Enum.at(0)`'s `nil`-on-empty behaviour (bare
  `Enum.min/1` would raise `Enum.EmptyError`).

  ## Flagged patterns

  | Pattern                                         | Suggested replacement          |
  | ----------------------------------------------- | ------------------------------ |
  | `Enum.sort/1 \|> Enum.at(0)`                    | `Enum.min(_, fn -> nil end)`   |
  | `Enum.sort/1 \|> Enum.reverse() \|> Enum.at(0)` | `Enum.max(_, fn -> nil end)`   |

  Only the `Enum.at(0)` terminal is rewritten. The `Enum.take(1)` and `hd/1`
  terminals are **deliberately not fixed**: `take(1)` returns a one-element
  *list* (`[min]`), not the scalar `Enum.min/1` returns; and `hd([])` raises
  `ArgumentError` where `Enum.min([])` raises `Enum.EmptyError` — neither is
  behaviour-preserving.

  ## Bad

      Enum.sort(list) |> Enum.at(0)
      Enum.sort(list) |> Enum.reverse() |> Enum.at(0)

  ## Good

      Enum.min(list, fn -> nil end)
      Enum.max(list, fn -> nil end)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  #
  # We use a custom recursive walk instead of Macro.prewalk so that
  # when we encounter a pipe node we analyse the *entire* flattened
  # pipeline as a unit.  We then recurse into each step's arguments
  # (but NOT into sub-pipes) — this prevents a longer pipeline like
  # `sort |> take(1) |> length()` from having its inner sub-pipe
  # `sort |> take(1)` independently flagged as a false positive.

  @impl true
  def check(ast, _opts) do
    ast
    |> collect_issues()
    |> Enum.reverse()
  end

  defp collect_issues({:|>, meta, _} = node) do
    pipeline = flatten_pipeline(node)

    own_issues =
      case analyze_pipeline(pipeline) do
        {:ok, var, op, reverses} ->
          issue = %Issue{
            rule: :no_sort_for_top_k,
            message: build_check_message(op, var, reverses),
            meta: %{line: Keyword.get(meta, :line)}
          }

          [issue]

        :error ->
          []
      end

    # Walk into each step's own arguments, not into the pipe structure
    step_issues = Enum.flat_map(pipeline, &collect_issues_from_step_args/1)
    own_issues ++ step_issues
  end

  defp collect_issues({left, right}) do
    collect_issues(left) ++ collect_issues(right)
  end

  defp collect_issues({_, _, args}) when is_list(args) do
    Enum.flat_map(args, &collect_issues/1)
  end

  defp collect_issues(list) when is_list(list) do
    Enum.flat_map(list, &collect_issues/1)
  end

  defp collect_issues(_), do: []

  defp collect_issues_from_step_args({_, _, args}) when is_list(args) do
    Enum.flat_map(args, &collect_issues/1)
  end

  defp collect_issues_from_step_args(_), do: []

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)
    RuleHelpers.patches_from_ast_transform(ast, source, &transform_ast/1)
  end

  #
  # We walk the AST top-down with a custom traversal instead of
  # Macro.prewalk/postwalk.  The key difference: when a pipe node
  # doesn't match a fixable pattern, we walk into its *right* (last
  # step) normally but treat the *left* (sub-pipeline) as a unit that
  # must NOT be independently fixed.  This prevents, e.g., the inner
  # pipe in `sort |> take(1) |> do_stuff()` from being turned into
  # `Enum.min(x) |> do_stuff()` which would change the return type.

  defp transform_ast(ast), do: transform_node(ast)

  # Pipe node — needs special handling
  defp transform_node({:|>, _, _} = node), do: fix_or_recurse_pipe(node)

  # 2-tuple (keyword pair, map pair, etc.)
  defp transform_node({left, right}), do: {transform_node(left), transform_node(right)}

  # Generic 3-tuple AST node with list arguments
  defp transform_node({_, _, args} = node) when is_list(args) do
    {form, meta, _} = node
    {transform_node(form), meta, Enum.map(args, &transform_node/1)}
  end

  # List of AST nodes (e.g. list literal, keyword list)
  defp transform_node(list) when is_list(list), do: Enum.map(list, &transform_node/1)

  # Leaf node (atom, number, string, variable, etc.)
  defp transform_node(node), do: node

  defp fix_or_recurse_pipe({:|>, meta, [left, right]} = node) do
    steps = flatten_pipeline(node)

    case fix_pipeline_steps(steps) do
      {:ok, replacement} ->
        # Walk into the replacement to fix any pipes nested inside the
        # sort argument (e.g. `sort(s |> f()) |> take(1)`)
        transform_node(replacement)

      :error ->
        # This pipe doesn't match a fixable single-element pattern.
        # Walk into the last step (right) normally, but the left side
        # is a sub-pipeline that must NOT be independently fixed.
        {:|>, meta, [transform_pipe_left(left), transform_node(right)]}
    end
  end

  # Walk into a sub-pipe's children without trying to fix the
  # sub-pipe itself at this level.
  defp transform_pipe_left({:|>, meta, [left, right]}) do
    {:|>, meta, [transform_pipe_left(left), transform_node(right)]}
  end

  defp transform_pipe_left(node), do: transform_node(node)

  defp fix_pipeline_steps([sort_expr | rest]) do
    with {:ok, arg} <- extract_sort_1(sort_expr) do
      fix_rest(arg, rest)
    end
  end

  defp fix_rest(arg, rest) do
    {reverses, after_reverses} = Enum.split_while(rest, &enum_reverse?/1)
    parity = rem(length(reverses), 2)

    case after_reverses do
      [single] ->
        # Only Enum.at(0) is behaviour-preservingly replaceable (with the
        # empty_fallback). take(1) returns a list and hd/1 raises a different
        # error on [], so neither is rewritten.
        case classify_terminal(single) do
          {:ok, :at, 0} -> {:ok, enum_call(min_or_max(parity), arg)}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp min_or_max(0), do: :min
  defp min_or_max(_), do: :max

  # Sourceror wraps integer literals in {:__block__, meta, [n]}.
  defp unwrap_int({:__block__, _, [n]}) when is_integer(n), do: n
  defp unwrap_int(_), do: nil

  defp classify_terminal({{:., _, [mod, :at]}, _, [idx_node]}) do
    idx = unwrap_int(idx_node)

    if idx != nil and enum_module?(mod), do: {:ok, :at, idx}, else: :error
  end

  defp classify_terminal(_), do: :error

  defp enum_reverse?({{:., _, [mod, :reverse]}, _, []}), do: enum_module?(mod)
  defp enum_reverse?(_), do: false

  # Only single-argument sort (ascending) — safe to determine min/max.
  defp extract_sort_1({{:., _, [mod, :sort]}, _, [arg]}) do
    if enum_module?(mod), do: {:ok, arg}, else: :error
  end

  defp extract_sort_1(_), do: :error

  defp enum_call(fun, arg) when fun in [:min, :max] do
    {{:., [], [{:__aliases__, [], [:Enum]}, fun]}, [], [arg, empty_fallback()]}
  end

  # `Enum.at(sorted, 0)` is `nil` on an empty collection; bare `Enum.min/1` would
  # raise. Preserve nil-on-empty with the empty_fallback. Parse it (rather than
  # hand-build the AST) so it carries the metadata Sourceror's renderer needs
  # when this fix re-renders via `patches_from_ast_transform`.
  defp empty_fallback, do: Sourceror.parse_string!("fn -> nil end")

  defp flatten_pipeline({:|>, _, [left, right]}) do
    flatten_pipeline(left) ++ [right]
  end

  defp flatten_pipeline(expr), do: [expr]

  defp analyze_pipeline([first | rest]) do
    with {:ok, var} <- extract_sort(first),
         {:ok, op, _k, reverses} <- find_topk(rest) do
      {:ok, var, op, reverses}
    end
  end

  # [arg | _] keeps compatibility with Enum.sort/2 calls — the check
  # still flags them, even though fix only handles single-arg sort.
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

  # Only match the Enum.at(0) terminal this module can fix behaviour-preservingly.
  defp extract_topk({{:., _, [mod, :at]}, _, [n_node]}) do
    if enum_module?(mod) and unwrap_int(n_node) == 0, do: {:ok, :at, 0}, else: :error
  end

  defp extract_topk({{:., _, [mod, :reverse]}, _, []}) do
    if enum_module?(mod), do: :reverse, else: :error
  end

  defp extract_topk(_), do: :error

  defp build_check_message(:at, var, reverses) do
    fun = if rem(reverses, 2) == 1, do: "Enum.max", else: "Enum.min"

    """
    Enum.sort/1 |> Enum.at(0) on `#{var}` is unnecessary sorting.
    Use #{fun} instead (empty_fallback preserves nil on []):
        #{fun}(#{var}, fn -> nil end)
    """
  end

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?(_), do: false

  # Handle capture arguments like &1
  defp var_name({:&, _, [n]}) when is_integer(n), do: :"&#{n}"
  defp var_name({name, _, context}) when is_atom(name) and is_atom(context), do: name
  defp var_name(_), do: nil
end
