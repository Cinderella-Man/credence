defmodule Credence.Pattern.PreferTupleDestructureAfterWithIndex do
  @moduledoc """
  Detects `Enum.map` calls that follow `Enum.with_index()` in a pipe chain
  but use a multi-argument anonymous function instead of destructuring the
  `{element, index}` tuple that `with_index/1` produces.

  ## Bad

      matrix
      |> Enum.with_index()
      |> Enum.map(fn row, index ->
        {index, Enum.count(row, &(&1 == 1))}
      end)

  `Enum.map/2` expects a 1-arity function, but `fn row, index ->` has arity 2.
  At runtime this raises `BadArityError` on every input because
  `Enum.with_index/1` emits `{element, index}` tuples — a single argument.

  ## Good

      matrix
      |> Enum.with_index()
      |> Enum.map(fn {row, index} ->
        {index, Enum.count(row, &(&1 == 1))}
      end)

  The tuple from `with_index/1` is destructured directly in the function
  head, which is both idiomatic and arity-correct.
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case detect_issue(node) do
          {:ok, issue} -> {node, [issue | issues]}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn node, patches ->
        case emit_patch(node) do
          {:ok, patch} -> {node, [patch | patches]}
          :error -> {node, patches}
        end
      end)

    Enum.reverse(patches)
  end

  # Detect the anti-pattern: `|> Enum.map(fn arg1, arg2 -> body end)` after
  # `Enum.with_index()` somewhere earlier in the pipe chain.
  defp detect_issue({:|>, _, [left, map_call]}) do
    with {:ok, fn_meta} <- match_enum_map_with_multi_arity_fn(map_call),
         true <- pipe_contains_with_index?(left) do
      line = Keyword.get(fn_meta, :line)

      {:ok,
       %Issue{
         rule: :prefer_tuple_destructure_after_with_index,
         message: build_message(),
         meta: %{line: line}
       }}
    else
      _ -> :error
    end
  end

  defp detect_issue(_), do: :error

  # Emit a patch for the anti-pattern: replace `fn var1, var2 ->` with `fn {var1, var2} ->`.
  defp emit_patch({:|>, _, [left, map_call]}) do
    with {:ok, _fn_meta} <- match_enum_map_with_multi_arity_fn(map_call),
         true <- pipe_contains_with_index?(left) do
      build_destructure_patch(map_call)
    else
      _ -> :error
    end
  end

  defp emit_patch(_), do: :error

  # Match `Enum.map(fn arg1, arg2 -> body end)` and return the fn's meta.
  defp match_enum_map_with_multi_arity_fn(
         {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _call_meta,
          [{:fn, fn_meta, [{:->, _, [args, _body]}]}]}
       )
       when is_list(args) and length(args) == 2 do
    {:ok, fn_meta}
  end

  defp match_enum_map_with_multi_arity_fn(_), do: :error

  # Walk the left side of a pipe to check if `Enum.with_index()` appears.
  defp pipe_contains_with_index?({:|>, _, [left, right]}) do
    with_index?(right) or pipe_contains_with_index?(left)
  end

  defp pipe_contains_with_index?(node), do: with_index?(node)

  defp with_index?({{:., _, [{:__aliases__, _, [:Enum]}, :with_index]}, _, args})
       when is_list(args), do: true

  defp with_index?(_), do: false

  # Build a patch that replaces `var1, var2` with `{var1, var2}` in the fn head.
  defp build_destructure_patch(
         {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _call_meta,
          [{:fn, _fn_meta, [{:->, _arrow_meta, [args, _body]}]}]}
       ) do
    [{var1, var1_meta, nil}, {var2, var2_meta, nil}] = args
    var1_name = Atom.to_string(var1)
    var2_name = Atom.to_string(var2)

    var1_line = Keyword.get(var1_meta, :line)
    var1_col = Keyword.get(var1_meta, :column)
    var2_line = Keyword.get(var2_meta, :line)
    var2_col = Keyword.get(var2_meta, :column)

    # Range: from start of first var to end of last var
    range = %Sourceror.Range{
      start: [line: var1_line, column: var1_col],
      end: [line: var2_line, column: var2_col + String.length(var2_name)]
    }

    change = "{#{var1_name}, #{var2_name}}"

    {:ok, %{range: range, change: change}}
  end

  defp build_message do
    """
    `Enum.map` called with a multi-argument function after `Enum.with_index()`.
    `with_index/1` emits `{element, index}` tuples, so `Enum.map` receives a
    single argument. Destructure the tuple in the function head:
        fn {elem, idx} -> ... end
    """
  end
end
