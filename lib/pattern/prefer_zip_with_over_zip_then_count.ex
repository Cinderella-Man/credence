defmodule Credence.Pattern.PreferZipWithOverZipThenCount do
  @moduledoc """
  Performance rule: Detects `Enum.zip/2` piped into `Enum.count/1` with a
  2-tuple destructuring predicate, and rewrites to `Enum.zip_with/3`.

  `Enum.zip/2` allocates an intermediate list of 2-tuples only to feed them
  to a counting predicate. `Enum.zip_with/3` applies the predicate inline
  during the zip, avoiding the intermediate allocation entirely.

  ## Bad

      a |> Enum.zip(b) |> Enum.count(fn {x, y} -> x != y end)
      Enum.count(Enum.zip(a, b), fn {x, y} -> x != y end)

  ## Good

      Enum.zip_with(a, b, fn x, y -> x != y end) |> Enum.count(& &1)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case check_node(node) do
          {:ok, issue} -> {node, [issue | issues]}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn node ->
      case build_replacement(node) do
        {:ok, replacement} -> replacement
        _ -> node
      end
    end)
  end

  # ── Check ─────────────────────────────────────────────────────────────

  # Pipeline: ... |> Enum.zip(b) |> Enum.count(fn {x, y} -> body end)
  defp check_node({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(fn [first, second] ->
      if zip_step?(first) and count_with_tuple_fn?(second) do
        {:ok, build_issue(first)}
      end
    end)
    |> case do
      {:ok, _} = result -> result
      _ -> :error
    end
  end

  # Nested: Enum.count(Enum.zip(a, b), fn {x, y} -> body end)
  defp check_node(
         {{:., meta, [{:__aliases__, _, [:Enum]}, :count]}, _,
          [{{:., _, [{:__aliases__, _, [:Enum]}, :zip]}, _, [_, _]}, fn_ast]}
       ) do
    if tuple_destructuring_fn?(fn_ast) do
      {:ok, build_issue_from_meta(meta)}
    else
      :error
    end
  end

  defp check_node(_), do: :error

  # ── Fix ───────────────────────────────────────────────────────────────

  defp build_replacement({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.find_value(fn {[first, second], idx} ->
      if zip_step?(first) and count_with_tuple_fn?(second) do
        {a_or_nil, b} = extract_zip_args(first)
        {fn_vars, fn_body} = extract_tuple_fn_from_count(second)

        before = Enum.take(steps, idx)
        after_ = Enum.drop(steps, idx + 2)

        zip_with_step = make_zip_with_step(a_or_nil, b, fn_vars, fn_body)
        count_step = make_count_truthy_step()

        pipeline = rebuild_pipeline(before, {:|>, [], [zip_with_step, count_step]}, after_)

        {:ok, pipeline}
      end
    end)
  end

  # Nested: Enum.count(Enum.zip(a, b), fn {x, y} -> body end)
  defp build_replacement(
         {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _,
          [{{:., _, [{:__aliases__, _, [:Enum]}, :zip]}, _, [a, b]}, fn_ast]}
       ) do
    if tuple_destructuring_fn?(fn_ast) do
      {fn_vars, fn_body} = extract_tuple_fn_from_fn(fn_ast)

      zip_with =
        {{:., [], [{:__aliases__, [], [:Enum]}, :zip_with]}, [],
         [a, b, {:fn, [], [{:->, [], [fn_vars, fn_body]}]}]}

      count = make_count_truthy_step()

      {:ok, {:|>, [], [zip_with, count]}}
    end
  end

  defp build_replacement(_), do: :skip

  # ── Predicates ────────────────────────────────────────────────────────

  defp zip_step?({{:., _, [{:__aliases__, _, [:Enum]}, :zip]}, _, args})
       when is_list(args) and length(args) in [1, 2],
       do: true

  defp zip_step?(_), do: false

  defp count_with_tuple_fn?({{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, [fn_ast]}) do
    tuple_destructuring_fn?(fn_ast)
  end

  defp count_with_tuple_fn?(_), do: false

  defp tuple_destructuring_fn?({:fn, _, clauses}) when length(clauses) == 1 do
    [{:->, _, [patterns, _body]}] = clauses

    case patterns do
      [{:__block__, _, [{{_, _, _}, {_, _, _}}]}] -> true
      [{{_, _, _}, {_, _, _}}] -> true
      _ -> false
    end
  end

  defp tuple_destructuring_fn?(_), do: false

  # ── Extraction ────────────────────────────────────────────────────────

  defp extract_zip_args({{:., _, [{:__aliases__, _, [:Enum]}, :zip]}, _, [b]}), do: {nil, b}

  defp extract_zip_args({{:., _, [{:__aliases__, _, [:Enum]}, :zip]}, _, [a, b]}), do: {a, b}

  defp extract_tuple_fn_from_count({{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, [fn_ast]}) do
    extract_tuple_fn_from_fn(fn_ast)
  end

  defp extract_tuple_fn_from_fn({:fn, _, [{:->, _, [patterns, body]}]}) do
    vars =
      case patterns do
        [{:__block__, _, [{x_var, y_var}]}] -> [x_var, y_var]
        [{x_var, y_var}] -> [x_var, y_var]
      end

    {vars, body}
  end

  # ── Builders ──────────────────────────────────────────────────────────

  defp make_zip_with_step(nil, b, fn_vars, fn_body) do
    # Pipe form: ... |> Enum.zip_with(b, fn x, y -> body end)
    {{:., [], [{:__aliases__, [], [:Enum]}, :zip_with]}, [],
     [b, {:fn, [], [{:->, [], [fn_vars, fn_body]}]}]}
  end

  defp make_zip_with_step(a, b, fn_vars, fn_body) do
    # Direct form: Enum.zip_with(a, b, fn x, y -> body end)
    {{:., [], [{:__aliases__, [], [:Enum]}, :zip_with]}, [],
     [a, b, {:fn, [], [{:->, [], [fn_vars, fn_body]}]}]}
  end

  defp make_count_truthy_step do
    {{:., [], [{:__aliases__, [], [:Enum]}, :count]}, [], [{:&, [], [{:&, [], [1]}]}]}
  end

  # ── Pipeline utilities ────────────────────────────────────────────────

  defp flatten_pipeline({:|>, _, [left, right]}),
    do: flatten_pipeline(left) ++ [right]

  defp flatten_pipeline(expr), do: [expr]

  defp rebuild_pipeline(before, step, after_) do
    all_steps = before ++ flatten_pipeline(step) ++ after_

    case all_steps do
      [] -> nil
      [single] -> single
      [first | rest] -> Enum.reduce(rest, first, fn s, acc -> {:|>, [], [acc, s]} end)
    end
  end

  # ── Issue builders ────────────────────────────────────────────────────

  defp build_issue(node) do
    {{:., meta, [_, :zip]}, _, _} = node
    build_issue_from_meta(meta)
  end

  defp build_issue_from_meta(meta) do
    %Issue{
      rule: :prefer_zip_with_over_zip_then_count,
      message: """
      `Enum.zip/2 |> Enum.count(fn {x, y} -> ... end)` allocates an intermediate \
      list of 2-tuples only to discard it. `Enum.zip_with/3` applies the function \
      inline and avoids the extra allocation entirely.

      Replace the pattern with `Enum.zip_with/3`:

          # Before (allocates intermediate tuples):
          Enum.zip(a, b) |> Enum.count(fn {x, y} -> x != y end)

          # After (no intermediate allocation):
          Enum.zip_with(a, b, fn x, y -> x != y end) |> Enum.count(& &1)
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
