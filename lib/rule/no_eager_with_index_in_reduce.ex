defmodule Credence.Rule.NoEagerWithIndexInReduce do
  @moduledoc """
  Performance rule: Detects `Enum.with_index/1` passed directly as the
  enumerable argument to `Enum.reduce/3` (or piped into it).

  `Enum.with_index/1` is eager — it traverses the entire list and allocates
  a new list of `{value, index}` tuples before `Enum.reduce` begins. This
  doubles memory consumption for large lists.

  ## Bad

      Enum.reduce(Enum.with_index(list), acc, fn {val, idx}, acc -> ... end)

      list |> Enum.with_index() |> Enum.reduce(acc, fn ...)

  ## Good

      # Option 1 (:stream strategy): Use Stream.with_index for lazy evaluation
      list |> Stream.with_index() |> Enum.reduce(acc, fn {val, idx}, acc -> ... end)

      # Option 2 (:reduce strategy): Track the index in the accumulator
      list
      |> Enum.reduce({0, acc}, fn val, {idx, acc} -> {idx + 1, ...} end)
      |> elem(1)

  ## Fix strategy

  Controlled by the `@fix_strategy` module attribute (default: `:stream`).
  Can also be overridden per-call via `opts[:fix_strategy]`.

      # Use stream (default):
      NoEagerWithIndexInReduce.fix(source, [])

      # Use reduce:
      NoEagerWithIndexInReduce.fix(source, fix_strategy: :reduce)

  The `:reduce` strategy falls back to `:stream` when the anonymous
  function shape doesn't match the expected `fn {val, idx}, acc -> body end`
  pattern (e.g. multi-clause fns or complex destructuring).
  """

  use Credence.Rule
  alias Credence.Issue

  @fix_strategy :stream

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Direct: Enum.reduce(Enum.with_index(list), acc, fn ...)
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta,
         [
           {{:., _, [{:__aliases__, _, [:Enum]}, :with_index]}, _, _} | _rest
         ]} = node,
        issues ->
          {node, [build_issue(meta) | issues]}

        # Piped: list |> Enum.with_index() |> Enum.reduce(acc, fn ...)
        {:|>, meta,
         [
           left,
           {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, _}
         ]} = node,
        issues ->
          if with_index_on_right?(left) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, opts) do
    strategy = Keyword.get(opts, :fix_strategy, @fix_strategy)

    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(&apply_fix(&1, strategy))
    |> Sourceror.to_string()
  end

  defp apply_fix(node, strategy) do
    case node do
      # Direct: Enum.reduce(Enum.with_index(list), initial_acc, fn_node)
      {{:., dot_meta, [{:__aliases__, _, [:Enum]}, :reduce]}, call_meta,
       [
         {{:., _, [{:__aliases__, _, [:Enum]}, :with_index]}, _, wi_args},
         initial_acc,
         fn_node
       ]} ->
        list = hd(wi_args)
        fix_direct(list, initial_acc, fn_node, dot_meta, call_meta, strategy)

      # Piped: ... |> Enum.with_index() |> Enum.reduce(initial_acc, fn_node)
      {:|>, pipe_meta,
       [
         left,
         {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, _} = reduce_call
       ]} ->
        if with_index_on_right?(left) do
          fix_pipe(left, reduce_call, pipe_meta, strategy)
        else
          node
        end

      other ->
        other
    end
  end

  # Stream strategy
  defp fix_direct(list, initial_acc, fn_node, dot_meta, call_meta, :stream) do
    {{:., dot_meta, [{:__aliases__, [], [:Enum]}, :reduce]}, call_meta,
     [
       {{:., [], [{:__aliases__, [], [:Stream]}, :with_index]}, [], [list]},
       initial_acc,
       fn_node
     ]}
  end

  # Reduce strategy
  defp fix_direct(list, initial_acc, fn_node, dot_meta, call_meta, :reduce) do
    case transform_fn_for_reduce(fn_node) do
      {:ok, new_fn} ->
        reduce_call =
          {{:., dot_meta, [{:__aliases__, [], [:Enum]}, :reduce]}, call_meta,
           [list, wrap_two_tuple({wrap_literal(0), initial_acc}), new_fn]}

        {:elem, [], [reduce_call, wrap_literal(1)]}

      :error ->
        fix_direct(list, initial_acc, fn_node, dot_meta, call_meta, :stream)
    end
  end

  # Stream strategy
  defp fix_pipe(left, reduce_call, pipe_meta, :stream) do
    {:|>, pipe_meta, [replace_enum_with_stream(left), reduce_call]}
  end

  # Reduce strategy
  defp fix_pipe(left, reduce_call, pipe_meta, :reduce) do
    {{:., rd_meta, [{:__aliases__, _, [:Enum]}, :reduce]}, rc_meta, reduce_args} =
      reduce_call

    case reduce_args do
      [initial_acc, fn_node] ->
        case transform_fn_for_reduce(fn_node) do
          {:ok, new_fn} ->
            deeper = strip_with_index(left)

            new_reduce =
              {{:., rd_meta, [{:__aliases__, [], [:Enum]}, :reduce]}, rc_meta,
               [wrap_two_tuple({wrap_literal(0), initial_acc}), new_fn]}

            {:|>, [],
             [
               {:|>, pipe_meta, [deeper, new_reduce]},
               {:elem, [], [wrap_literal(1)]}
             ]}

          :error ->
            fix_pipe(left, reduce_call, pipe_meta, :stream)
        end

      _ ->
        fix_pipe(left, reduce_call, pipe_meta, :stream)
    end
  end

  # ── Literal wrapping ────────────────────────────────────────────
  # Sourceror.to_string/1 → Code.Formatter requires __block__ nodes
  # to carry a :token key in their metadata so the formatter knows
  # how to render the literal.

  defp wrap_literal(int) when is_integer(int),
    do: {:__block__, [token: Integer.to_string(int)], [int]}

  # ── Fn transformation for :reduce strategy ───
  #
  # Transforms:
  #   fn {val, idx}, acc -> body end
  # Into:
  #   fn val, {idx, acc} -> {idx + 1, body} end
  #
  # Returns :error if the fn shape doesn't match (falls back to :stream).

  defp transform_fn_for_reduce({:fn, fn_meta, clauses}) when is_list(clauses) do
    results = Enum.map(clauses, &transform_clause/1)

    if Enum.all?(results, &match?({:ok, _}, &1)) do
      new_clauses = Enum.map(results, fn {:ok, clause} -> clause end)
      {:ok, {:fn, fn_meta, new_clauses}}
    else
      :error
    end
  end

  defp transform_fn_for_reduce(_), do: :error

  defp transform_clause({:->, arrow_meta, [args, body]}) do
    case extract_with_index_params(args) do
      {:ok, val_node, idx_node, acc_node} ->
        new_args = [val_node, wrap_two_tuple({idx_node, acc_node})]
        new_body = wrap_last_expr(body, idx_node)
        {:ok, {:->, arrow_meta, [new_args, new_body]}}

      :error ->
        :error
    end
  end

  defp transform_clause(_), do: :error

  # Extracts val, idx, acc from fn clause args like [{val, idx}, acc].
  #
  # Sourceror wraps literal 2-tuples in {:__block__, meta, [{a, b}]}
  # to attach position metadata (the standard Elixir AST cannot attach
  # metadata to bare 2-tuples). We handle both representations so the
  # code works regardless of how the AST was parsed.
  defp extract_with_index_params([tuple_pat, acc_node]) do
    with {:ok, val_node, idx_node} <- unwrap_two_tuple(tuple_pat),
         true <- variable_node?(val_node),
         true <- variable_node?(idx_node),
         true <- variable_node?(acc_node) do
      {:ok, val_node, idx_node, acc_node}
    else
      _ -> :error
    end
  end

  defp extract_with_index_params(_), do: :error

  # Sourceror form: 2-tuple wrapped in __block__ for metadata
  defp unwrap_two_tuple({:__block__, _, [{a, b}]}), do: {:ok, a, b}
  # Standard Code.string_to_quoted form: bare 2-tuple
  defp unwrap_two_tuple({a, b}) when is_tuple(a) and tuple_size(a) == 3, do: {:ok, a, b}
  defp unwrap_two_tuple(_), do: :error

  defp variable_node?({name, _meta, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp variable_node?(_), do: false

  # Wraps a bare {a, b} Elixir term into {:__block__, [], [{a, b}]}
  # so Sourceror.to_string/1 renders it as a proper two-element tuple.
  defp wrap_two_tuple({a, b}), do: {:__block__, [], [{a, b}]}

  # Wraps the last expression in a block (or a single expression)
  # with {idx + 1, last_expr}
  defp wrap_last_expr({:__block__, block_meta, exprs}, idx_node) do
    {init, [last]} = Enum.split(exprs, -1)
    {:__block__, block_meta, init ++ [index_bump_tuple(idx_node, last)]}
  end

  defp wrap_last_expr(single_expr, idx_node) do
    index_bump_tuple(idx_node, single_expr)
  end

  # Builds {idx + 1, expr} as a Sourceror-compatible AST node.
  defp index_bump_tuple({name, _, _}, expr) do
    wrap_two_tuple({{:+, [], [{name, [], nil}, wrap_literal(1)]}, expr})
  end

  # Replaces Enum.with_index → Stream.with_index in the pipe chain
  defp replace_enum_with_stream(
         {{:., dot_meta, [{:__aliases__, _, [:Enum]}, :with_index]}, call_meta, args}
       ) do
    {{:., dot_meta, [{:__aliases__, [], [:Stream]}, :with_index]}, call_meta, args}
  end

  defp replace_enum_with_stream({:|>, pipe_meta, [deeper, right]}) do
    if with_index_call?(right) do
      {:|>, pipe_meta, [deeper, replace_enum_with_stream(right)]}
    else
      {:|>, pipe_meta, [deeper, right]}
    end
  end

  defp replace_enum_with_stream(node), do: node

  # Removes the Enum.with_index step, returning what was piped into it
  defp strip_with_index(
         {:|>, _, [deeper, {{:., _, [{:__aliases__, _, [:Enum]}, :with_index]}, _, _}]}
       ) do
    deeper
  end

  defp strip_with_index({{:., _, [{:__aliases__, _, [:Enum]}, :with_index]}, _, [list]}) do
    list
  end

  defp strip_with_index(node), do: node

  defp with_index_on_right?({:|>, _, [_, right]}), do: with_index_call?(right)
  defp with_index_on_right?(node), do: with_index_call?(node)

  defp with_index_call?({{:., _, [{:__aliases__, _, [:Enum]}, :with_index]}, _, _}), do: true
  defp with_index_call?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :no_eager_with_index_in_reduce,
      message:
        "`Enum.with_index/1` eagerly allocates a new list of tuples before `Enum.reduce/3` begins. " <>
          "Use `Stream.with_index/1` for lazy evaluation, or track the index in the accumulator.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
