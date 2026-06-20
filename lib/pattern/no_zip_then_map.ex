defmodule Credence.Pattern.NoZipThenMap do
  @moduledoc """
  Detects `Enum.zip/2` followed by `Enum.map/2` that destructures the
  resulting 2-tuples, which can be replaced by `Enum.zip_with/3`.

  ## Why this matters

  `Enum.zip(a, b) |> Enum.map(fn {x, y} -> expr end)` allocates an
  intermediate list of 2-tuples only to immediately destructure them.
  `Enum.zip_with/3` (available since Elixir 1.14) combines both steps
  into a single pass without the intermediate allocation.

  ## Bad

      Enum.zip(names, scores)
      |> Enum.map(fn {name, score} -> {name, score * 2} end)

      Enum.map(Enum.zip(names, scores), fn {name, score} ->
        {name, score * 2}
      end)

      names
      |> Enum.zip(scores)
      |> Enum.map(fn {name, score} -> {name, score * 2} end)

  ## Good

      Enum.zip_with(names, scores, fn name, score ->
        {name, score * 2}
      end)

  ## Scope

  Flags when ALL of these hold:
  - `Enum.zip/2` is called with two arguments.
  - Its result is passed to `Enum.map/2` (via pipe or nesting).
  - The `Enum.map` function destructures a 2-tuple into two variables.

  Does NOT flag:
  - `Enum.zip/2` alone (no following `Enum.map`).
  - `Enum.map` whose function does not destructure a 2-tuple.
  - `Enum.zip/1` (a list of enumerables) at the head of a pipe — this is the
    real `Enum.zip/1`, not a pipe-elided `zip/2`, and is not convertible.
  - Guarded fns (`fn {x, y} when ... -> ... end`) — dropping or rebuilding the
    guard is out of scope, so these are left untouched.
  - Already-idiomatic `Enum.zip_with/3`.

  ## Auto-fix

  Replaces the `Enum.zip |> Enum.map` pair with `Enum.zip_with/3`,
  transforming the fn's tuple pattern into separate parameters.
  """

  use Credence.Pattern.Rule

  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipe: ... |> Enum.map(fn {x, y} -> ...) where rightmost on left is Enum.zip
        {:|>, _,
         [
           left,
           {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, map_meta, [fn_arg]}
         ]} = node,
        acc ->
          with true <- two_tuple_fn?(fn_arg),
               false <- guarded_fn?(fn_arg),
               zip_node = rightmost(left),
               true <- valid_zip_for_pipe?(zip_node, left) do
            {node, [build_issue(map_meta) | acc]}
          else
            _ -> {node, acc}
          end

        # Nested: Enum.map(Enum.zip(a, b), fn {x, y} -> ...)
        {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, map_meta,
         [
           {{:., _, [{:__aliases__, _, [:Enum]}, :zip]}, _, [_, _]},
           fn_arg
         ]} = node,
        acc ->
          if two_tuple_fn?(fn_arg) and not guarded_fn?(fn_arg) do
            {node, [build_issue(map_meta) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, source: source) do
    # `transform_node/1` matches a single `Enum.zip |> Enum.map` (or nested) node;
    # it must be WALKED over the tree, otherwise it only ever sees the module root
    # and the fix is a silent no-op for every real (nested) occurrence.
    RuleHelpers.patches_from_ast_transform(ast, source, fn input ->
      Macro.postwalk(input, &transform_node/1)
    end)
  end

  # --- transform ---

  # Pipe: ... |> Enum.map(fn {x, y} -> body end)
  defp transform_node(
         {:|>, _pipe_meta,
          [
            left,
            {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _map_meta, [fn_arg]}
          ]} = node
       ) do
    with true <- two_tuple_fn?(fn_arg),
         false <- guarded_fn?(fn_arg),
         zip_node = rightmost(left),
         true <- valid_zip_for_pipe?(zip_node, left),
         {:ok, x, y, body} <- extract_fn_vars(fn_arg) do
      zip_with = build_zip_with_from_zip(zip_node, x, y, body)
      replace_in_pipe(left, zip_node, zip_with)
    else
      _ -> node
    end
  end

  # Nested: Enum.map(Enum.zip(a, b), fn {x, y} -> body end)
  defp transform_node(
         {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _map_meta,
          [
            {{:., _, [{:__aliases__, _, [:Enum]}, :zip]}, _, [a, b]},
            fn_arg
          ]} = node
       ) do
    with true <- two_tuple_fn?(fn_arg),
         false <- guarded_fn?(fn_arg),
         {:ok, x, y, body} <- extract_fn_vars(fn_arg) do
      build_zip_with_call(a, b, x, y, body)
    else
      _ -> node
    end
  end

  defp transform_node(node), do: node

  # --- predicates ---

  defp two_tuple_fn?({:fn, _, clauses}) do
    case clauses do
      [{:->, _, [params, _body]}] ->
        two_tuple_params?(params)

      _ ->
        false
    end
  end

  defp two_tuple_fn?(_), do: false

  defp two_tuple_params?(params) do
    extract_2tuple_from_params(params) != nil
  end

  # Walk the params to find a 2-tuple of variables
  defp extract_2tuple_from_params(params) when is_list(params) do
    Enum.find_value(params, fn param ->
      find_2tuple_vars(param)
    end)
  end

  defp extract_2tuple_from_params(_), do: nil

  # Direct 2-tuple: {x, y}
  defp find_2tuple_vars({x, y})
       when is_tuple(x) and is_tuple(y) and tuple_size(x) == 3 and tuple_size(y) == 3 do
    case {x, y} do
      {{name1, _, ctx1}, {name2, _, ctx2}}
      when is_atom(name1) and is_atom(ctx1) and is_atom(name2) and is_atom(ctx2) ->
        {x, y}

      _ ->
        nil
    end
  end

  # Block-wrapped: {:__block__, _, [{x, y}]}
  defp find_2tuple_vars({:__block__, _, [inner]}), do: find_2tuple_vars(inner)

  # When-guarded: {:when, _, [pattern, guard]}
  defp find_2tuple_vars({:when, _, [pattern, _guard]}), do: find_2tuple_vars(pattern)

  defp find_2tuple_vars(_), do: nil

  defp guarded_fn?({:fn, _, [{:->, _, [params, _]}]}) do
    Enum.any?(params, &param_has_guard?/1)
  end

  defp guarded_fn?(_), do: false

  defp param_has_guard?({:when, _, _}), do: true
  defp param_has_guard?({:__block__, _, [inner]}), do: param_has_guard?(inner)
  defp param_has_guard?(_), do: false

  # Is `zip_node` (the rightmost node of the pipe's left side) a convertible
  # Enum.zip call?
  #
  # - 2-arg `Enum.zip(a, b)` is always convertible: both enumerables are
  #   syntactically present, regardless of whether it sits at the pipe head
  #   or is itself pipe-fed.
  # - 1-arg `Enum.zip(b)` is only convertible when it is genuinely pipe-fed
  #   (`left` is a `|>` chain whose rightmost element is this node, so the
  #   first enumerable comes from the pipe and the call is really `zip/2`).
  #   At the pipe head (`left == zip_node`) a 1-arg call is the real
  #   `Enum.zip/1` over a list of enumerables — NOT `zip/2` — and must not be
  #   rewritten.
  defp valid_zip_for_pipe?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :zip]}, _, [_, _]},
         _left
       ),
       do: true

  defp valid_zip_for_pipe?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :zip]}, _, [_]} = zip_node,
         left
       ),
       do: left != zip_node

  defp valid_zip_for_pipe?(_, _), do: false

  # --- extraction helpers ---

  defp extract_fn_vars({:fn, _meta, [{:->, _, [params, body]}]}) do
    case extract_2tuple_from_params(params) do
      {x, y} -> {:ok, x, y, body}
      nil -> :error
    end
  end

  defp extract_fn_vars(_), do: :error

  # --- AST builders ---

  # Build Enum.zip_with(a, b, fn x, y -> body end)
  defp build_zip_with_call(a, b, x, y, body) do
    fn_expr = {:fn, [], [{:->, [], [[x, y], body]}]}

    {{:., [], [{:__aliases__, [], [:Enum]}, :zip_with]}, [], [a, b, fn_expr]}
  end

  # Build Enum.zip_with from an existing Enum.zip node, preserving the args.
  # Handles both 2-arg (standalone) and 1-arg (pipe context) zip.
  defp build_zip_with_from_zip(
         {{:., _, [{:__aliases__, _, [:Enum]}, :zip]}, _, [a, b]},
         x,
         y,
         body
       ) do
    build_zip_with_call(a, b, x, y, body)
  end

  # 1-arg zip in pipe: Enum.zip(b). First arg comes from pipe context.
  defp build_zip_with_from_zip(
         {{:., _, [{:__aliases__, _, [:Enum]}, :zip]}, _, [b]},
         x,
         y,
         body
       ) do
    # We need the first arg from the pipe. This is handled by replace_in_pipe.
    # Return a partial call; replace_in_pipe will handle the first arg.
    {:zip_with_1arg, b, x, y, body}
  end

  # Replace `target` in the pipe chain rooted at `left` with `replacement`.
  # Returns the new pipe chain (or just replacement if left == target).
  defp replace_in_pipe(left, target, replacement) do
    case left do
      ^target ->
        replacement

      {:|>, meta, [deeper, ^target]} ->
        case replacement do
          {:zip_with_1arg, b, x, y, body} ->
            # left is `deeper |> Enum.zip(b)`, deeper is the first arg
            {:|>, meta, [deeper, build_zip_with_1arg(b, x, y, body)]}

          _ ->
            {:|>, meta, [deeper, replacement]}
        end

      {:|>, meta, [deeper, other]} ->
        {:|>, meta, [replace_in_pipe(deeper, target, replacement), other]}

      other ->
        other
    end
  end

  # Build Enum.zip_with(b, fn x, y -> body end) for pipe context (1-arg)
  defp build_zip_with_1arg(b, x, y, body) do
    fn_expr = {:fn, [], [{:->, [], [[x, y], body]}]}

    {{:., [], [{:__aliases__, [], [:Enum]}, :zip_with]}, [], [b, fn_expr]}
  end

  # --- AST helpers ---

  defp rightmost({:|>, _, [_left, right]}), do: rightmost(right)
  defp rightmost(other), do: other

  # --- issue builder ---

  defp build_issue(meta) do
    %Issue{
      rule: :no_zip_then_map,
      message:
        "`Enum.zip/2` followed by `Enum.map/2` with tuple destructuring " <>
          "allocates an intermediate list. Use `Enum.zip_with/3` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
