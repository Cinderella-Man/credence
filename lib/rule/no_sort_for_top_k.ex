defmodule Credence.Rule.NoSortForTopK do
  @moduledoc """
  Detects inefficient patterns where a full sort is performed only to
  retrieve a single element (the minimum or maximum).

  Sorting an entire collection is O(n log n). When only the minimum or
  maximum element is needed, `Enum.min/1` or `Enum.max/1` provides the
  same result in O(n) without allocating a sorted intermediate list.

  ## Flagged patterns

  | Pattern                                           | Suggested replacement |
  | ------------------------------------------------- | --------------------- |
  | `Enum.sort/1 \|> Enum.take(1)`                    | `Enum.min/1`          |
  | `Enum.sort/1 \|> hd/1`                            | `Enum.min/1`          |
  | `Enum.sort/1 \|> Enum.at(0)`                      | `Enum.min/1`          |
  | `Enum.sort/1 \|> Enum.reverse() \|> Enum.take(1)` | `Enum.max/1`          |
  | `Enum.sort/1 \|> Enum.reverse() \|> hd/1`         | `Enum.max/1`          |
  | `Enum.sort/1 \|> Enum.reverse() \|> Enum.at(0)`   | `Enum.max/1`          |

  These patterns are **automatically fixable**.

  ## Bad

      Enum.sort(list) |> Enum.take(1)
      Enum.sort(list) |> Enum.reverse() |> hd()

  ## Good

      Enum.min(list)
      Enum.max(list)
  """

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  # ── Check ────────────────────────────────────────────────────────
  #
  # We use a custom recursive walk instead of Macro.prewalk so that
  # when we encounter a pipe node we analyse the *entire* flattened
  # pipeline as a unit.  We then recurse into each step's arguments
  # (but NOT into sub-pipes) — this prevents a longer pipeline like
  # `sort |> take(1) |> length()` from having its inner sub-pipe
  # `sort |> take(1)` independently flagged as a false positive.
  # ────────────────────────────────────────────────────────────────

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

  # ── Fix ──────────────────────────────────────────────────────────

  @impl true
  def fix(source, _opts) do
    result =
      source
      |> Sourceror.parse_string!()
      |> transform_ast()
      |> Sourceror.to_string()

    # Sourceror.to_string/1 strips trailing newlines; preserve them
    # so that round-tripping unchanged code stays identical.
    if String.ends_with?(source, "\n") and not String.ends_with?(result, "\n") do
      result <> "\n"
    else
      result
    end
  end

  # ── Fix: AST transformation ──────────────────────────────────────
  #
  # We walk the AST top-down with a custom traversal instead of
  # Macro.prewalk/postwalk.  The key difference: when a pipe node
  # doesn't match a fixable pattern, we walk into its *right* (last
  # step) normally but treat the *left* (sub-pipeline) as a unit that
  # must NOT be independently fixed.  This prevents, e.g., the inner
  # pipe in `sort |> take(1) |> do_stuff()` from being turned into
  # `Enum.min(x) |> do_stuff()` which would change the return type.
  # ──────────────────────────────────────────────────────────────────

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

  # ── Pipeline analysis for fix ────────────────────────────────────

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
        case classify_terminal(single) do
          {:ok, :take, 1} -> {:ok, enum_call(min_or_max(parity), arg)}
          {:ok, :hd, _} -> {:ok, enum_call(min_or_max(parity), arg)}
          {:ok, :at, 0} -> {:ok, enum_call(min_or_max(parity), arg)}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp min_or_max(0), do: :min
  defp min_or_max(_), do: :max

  # Sourceror wraps bare integer literals in {:__block__, meta, [n]},
  # so we need to unwrap before comparing.
  defp unwrap_int({:__block__, _, [n]}) when is_integer(n), do: n
  defp unwrap_int(n) when is_integer(n), do: n
  defp unwrap_int(_), do: nil

  defp classify_terminal({{:., _, [mod, :take]}, _, [k_node]}) do
    k = unwrap_int(k_node)

    if k != nil and enum_module?(mod), do: {:ok, :take, k}, else: :error
  end

  defp classify_terminal({:hd, _, []}), do: {:ok, :hd, 1}

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
    {{:., [], [{:__aliases__, [], [:Enum]}, fun]}, [], [arg]}
  end

  # ── Check helpers ────────────────────────────────────────────────

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

  # Only match the single-element terminals this module can fix.
  defp extract_topk({{:., _, [mod, :take]}, _, [1]}) do
    if enum_module?(mod), do: {:ok, :take, 1}, else: :error
  end

  defp extract_topk({:hd, _, []}), do: {:ok, :hd, 1}

  defp extract_topk({{:., _, [mod, :at]}, _, [0]}) do
    if enum_module?(mod), do: {:ok, :at, 0}, else: :error
  end

  defp extract_topk({{:., _, [mod, :reverse]}, _, []}) do
    if enum_module?(mod), do: :reverse, else: :error
  end

  defp extract_topk(_), do: :error

  defp build_check_message(op, var, reverses) do
    is_reversed = rem(reverses, 2) == 1
    fun = if is_reversed, do: "Enum.max", else: "Enum.min"

    case op do
      :take ->
        """
        Enum.sort/1 |> Enum.take(1) on `#{var}` is unnecessary O(n log n).
        Use #{fun}/1 instead for O(n):
            #{fun}(#{var})
        """

      :hd ->
        """
        Enum.sort/1 |> hd/1 on `#{var}` is inefficient.
        Use #{fun}/1 instead:
            #{fun}(#{var})
        """

      :at ->
        """
        Enum.sort/1 |> Enum.at(0) on `#{var}` is unnecessary sorting.
        Use #{fun}/1 instead:
            #{fun}(#{var})
        """
    end
  end

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?(_), do: false

  # Handle capture arguments like &1
  defp var_name({:&, _, [n]}) when is_integer(n), do: :"&#{n}"
  defp var_name({name, _, context}) when is_atom(name) and is_atom(context), do: name
  defp var_name(_), do: nil
end
