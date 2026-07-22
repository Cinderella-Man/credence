defmodule Credence.Pattern.PreferZipWithOverZipThenCount do
  @moduledoc """
  Detects `Enum.zip/2` whose result goes straight into `Enum.count/2` with a
  predicate that destructures the 2-tuples, and rewrites the pair to
  `Enum.zip_with/3` piped into `Enum.count(& &1)`.

  ## Why this matters

  `Enum.zip(a, b) |> Enum.count(fn {x, y} -> pred end)` allocates an
  intermediate list of 2-tuples only to destructure and discard them.
  `Enum.zip_with/3` applies the predicate while zipping, and
  `Enum.count(& &1)` counts the truthy results — the same truthy-counting
  `Enum.count/2` does, so the answer is identical.

  ## Bad

      a |> Enum.zip(b) |> Enum.count(fn {x, y} -> x != y end)
      Enum.zip(a, b) |> Enum.count(fn {x, y} -> x != y end)
      Enum.count(Enum.zip(a, b), fn {x, y} -> x != y end)

  ## Good

      a |> Enum.zip_with(b, fn x, y -> x != y end) |> Enum.count(& &1)

  ## Scope

  Flags only when ALL of these hold:

  - the count step is `Enum.count/2` with a single-clause, unguarded `fn`
    whose only parameter is a 2-tuple of plain variables
    (`fn {x, y} -> ... end`);
  - the zip is convertible: a 2-argument `Enum.zip(a, b)` at the pipe head
    (or nested as count's first argument), or a 1-argument `|> Enum.zip(b)`
    that is genuinely pipe-fed.

  Does NOT flag:

  - `Enum.zip/1` at the pipe head (`Enum.zip(enums) |> ...`) — that is the
    real `zip/1` over a list of enumerables, and the corresponding
    `Enum.zip_with/2` calls its fun with a *list*, so the rewrite would raise
    `BadArityError`;
  - a 2-argument zip that is itself pipe-fed (`x |> Enum.zip(a, b)`) — a call
    to the nonexistent `Enum.zip/3`;
  - `Enum.count(Enum.zip(a, b), fn ...)` appearing as a pipe step — a call to
    the nonexistent `Enum.count/3`;
  - predicates whose pattern is not two plain variables (pins, literals,
    nested destructuring, guards, extra parameters, multiple clauses,
    captures) — refutable patterns can fail mid-enumeration, and moving the
    match from `count` into `zip_with` changes when the sources stop being
    consumed;
  - `Enum.zip |> Enum.count()` without a predicate, and already-idiomatic
    `Enum.zip_with/3`.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  defguardp is_plain_var(t)
            when is_tuple(t) and tuple_size(t) == 3 and is_atom(elem(t, 0)) and
                   is_atom(elem(t, 2))

  @impl true
  def check(ast, _opts) do
    skip = piped_count2_nodes(ast)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case match_node(node, skip) do
          {:ok, meta, _parts} -> {node, [build_issue(meta) | acc]}
          :no -> {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    skip = piped_count2_nodes(ast)

    Credence.RuleHelpers.patches_from_postwalk(ast, fn node ->
      case match_node(node, skip) do
        {:ok, _meta, parts} -> rewrite(parts)
        :no -> node
      end
    end)
  end

  # ── Matching (shared by check and fix, so they always agree) ──────────

  # Pipe form: <left> |> Enum.count(fn {x, y} -> body end).
  # Examining only the top adjacent pair of each `|>` node visits every
  # consecutive step-pair exactly once, so a flagged pipeline produces
  # exactly one issue even when more steps follow the count.
  defp match_node(
         {:|>, _,
          [left, {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, [fn_ast]}]},
         _skip
       ) do
    with {:ok, x, y, body} <- tuple_vars_fn(fn_ast),
         {:ok, meta, zip} <- convertible_zip(left) do
      {:ok, meta, {:pipe, zip, x, y, body}}
    else
      _ -> :no
    end
  end

  # Nested form: Enum.count(Enum.zip(a, b), fn {x, y} -> body end).
  # Skipped when the node sits in pipe-step position (see piped_count2_nodes/1).
  defp match_node(
         {{:., meta, [{:__aliases__, _, [:Enum]}, :count]}, _,
          [{{:., _, [{:__aliases__, _, [:Enum]}, :zip]}, _, [a, b]}, fn_ast]} = node,
         skip
       ) do
    with false <- MapSet.member?(skip, node),
         {:ok, x, y, body} <- tuple_vars_fn(fn_ast) do
      {:ok, meta, {:nested, a, b, x, y, body}}
    else
      _ -> :no
    end
  end

  defp match_node(_, _), do: :no

  # 2-arg zip at the pipe head: Enum.zip(a, b) |> Enum.count(...).
  defp convertible_zip({{:., meta, [{:__aliases__, _, [:Enum]}, :zip]}, _, [a, b]}) do
    {:ok, meta, {:head, a, b}}
  end

  # Pipe-fed 1-arg zip: ... |> Enum.zip(b) |> Enum.count(...). The first
  # enumerable comes from the pipe, so this really is `zip/2`.
  defp convertible_zip(
         {:|>, lmeta, [deeper, {{:., meta, [{:__aliases__, _, [:Enum]}, :zip]}, _, [b]}]}
       ) do
    {:ok, meta, {:piped, lmeta, deeper, b}}
  end

  defp convertible_zip(_), do: :no

  # The predicate must be a single-clause, unguarded fn whose sole parameter
  # is a 2-tuple of plain variables — that pattern can never fail on zip's
  # 2-tuples, so moving it into `zip_with` cannot change behaviour.
  defp tuple_vars_fn({:fn, _, [{:->, _, [[pattern], body]}]}) do
    case unwrap_block(pattern) do
      {x, y} when is_plain_var(x) and is_plain_var(y) -> {:ok, x, y, body}
      _ -> :error
    end
  end

  defp tuple_vars_fn(_), do: :error

  defp unwrap_block({:__block__, _, [inner]}), do: inner
  defp unwrap_block(other), do: other

  # `Enum.count(zip, fn)` sitting in pipe-step position is a call to the
  # nonexistent `Enum.count/3` — collect those RHS nodes so the nested-form
  # clause never fires on them. Line/column metadata makes each collected
  # node unique to its source position.
  defp piped_count2_nodes(ast) do
    {_ast, acc} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:|>, _, [_left, {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, [_, _]} = right]} =
            node,
        acc ->
          {node, MapSet.put(acc, right)}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  # ── Rewriting ─────────────────────────────────────────────────────────

  defp rewrite({:pipe, {:head, a, b}, x, y, body}) do
    pipe(zip_with_call([a, b], x, y, body), count_truthy())
  end

  defp rewrite({:pipe, {:piped, lmeta, deeper, b}, x, y, body}) do
    pipe({:|>, lmeta, [deeper, zip_with_call([b], x, y, body)]}, count_truthy())
  end

  defp rewrite({:nested, a, b, x, y, body}) do
    pipe(zip_with_call([a, b], x, y, body), count_truthy())
  end

  defp pipe(left, right), do: {:|>, [], [left, right]}

  defp zip_with_call(enum_args, x, y, body) do
    fn_expr = {:fn, [], [{:->, [], [[x, y], body]}]}

    {{:., [], [{:__aliases__, [], [:Enum]}, :zip_with]}, [], enum_args ++ [fn_expr]}
  end

  defp count_truthy do
    {{:., [], [{:__aliases__, [], [:Enum]}, :count]}, [], [{:&, [], [{:&, [], [1]}]}]}
  end

  # ── Issue ─────────────────────────────────────────────────────────────

  defp build_issue(meta) do
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
