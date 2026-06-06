defmodule Credence.Pattern.PreferEnumSplit do
  @moduledoc """
  Performance rule: collapses two adjacent assignments that take and drop the
  same prefix of the same list variable into a single `Enum.split/2`, which
  produces both results in one pass.

  ## Bad

      first = Enum.take(items, 3)
      rest = Enum.drop(items, 3)

  ## Good

      {first, rest} = Enum.split(items, 3)

  ## Scope (the safe core)

  Fires only when ALL of these hold for two **adjacent** statements in a block:

  - `a = Enum.take(src, n)` immediately followed by `b = Enum.drop(src, n)`.
  - `src` is the **same simple variable** in both calls.
  - `n` is the **same non-negative integer literal** in both calls.
  - `a` and `b` are simple variable names with `a != b`.
  - `a` is not the source variable `src` (otherwise the `take` rebinds the
    list the `drop` then reads — a different value).

  ## Does NOT fire (deliberately dropped — not provably behaviour-preserving)

  - **Negative or variable counts.** `Enum.split(l, n)` only equals
    `{Enum.take(l, n), Enum.drop(l, n)}` for non-negative `n`; for negative `n`
    the two halves swap. A variable count's sign is unknown, so it is skipped.
  - **`Enum.reverse(Enum.drop(...))`** — would need a fresh `rest` binding and a
    second statement.
  - **Piped forms** (`src |> Enum.take(n)`).
  - **Non-adjacent** take/drop (statements between them may rebind `src`).
  - **`take` rebinding `src`** (`src = Enum.take(src, n)`).
  - `take` or `drop` alone, different sources, different counts, unbound calls.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_, issues} =
      Macro.prewalk(ast, [], fn
        {:__block__, _, stmts} = node, acc when is_list(stmts) ->
          {_new_stmts, lines} = collapse(stmts)

          {node, acc ++ Enum.map(lines, &issue/1)}

        node, acc ->
          {node, acc}
      end)

    issues
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.get(opts, :source) || Sourceror.to_string(ast)
    RuleHelpers.patches_from_ast_transform(ast, source, &collapse_blocks/1)
  end

  defp collapse_blocks(ast) do
    Macro.prewalk(ast, fn
      {:__block__, meta, stmts} when is_list(stmts) ->
        {new_stmts, _lines} = collapse(stmts)
        {:__block__, meta, new_stmts}

      node ->
        node
    end)
  end

  # Shared engine for check and fix: walk a statement list, merging each
  # adjacent take/drop pair into one `Enum.split/2` assignment. Returns the
  # rewritten statement list and the drop-line of every merged pair, so check
  # (issues) and fix (rewrite) can never disagree about which pairs are safe.
  defp collapse([s1, s2 | rest]) do
    case merge_pair(s1, s2) do
      {:ok, merged, line} ->
        {stmts, lines} = collapse(rest)
        {[merged | stmts], [line | lines]}

      :no ->
        {stmts, lines} = collapse([s2 | rest])
        {[s1 | stmts], lines}
    end
  end

  defp collapse(stmts), do: {stmts, []}

  defp merge_pair(
         {:=, _m1, [{a, _, nil}, take]},
         {:=, m2, [{b, _, nil}, drop]}
       )
       when is_atom(a) and is_atom(b) and a != b do
    with {src, n} <- enum_call(:take, take),
         {^src, ^n} <- enum_call(:drop, drop),
         true <- a != src do
      merged =
        {:=, [],
         [
           {{a, [], nil}, {b, [], nil}},
           {{:., [], [{:__aliases__, [], [:Enum]}, :split]}, [], [{src, [], nil}, n]}
         ]}

      {:ok, merged, Keyword.get(m2, :line)}
    else
      _ -> :no
    end
  end

  defp merge_pair(_, _), do: :no

  # Enum.<op>(src_var, non_neg_integer_literal) -> {src_name, n}
  defp enum_call(op, {{:., _, [{:__aliases__, _, [:Enum]}, op]}, _, [src, count]}) do
    with src_name when is_atom(src_name) <- var_name(src),
         n when is_integer(n) and n >= 0 <- count_literal(count) do
      {src_name, n}
    else
      _ -> nil
    end
  end

  defp enum_call(_, _), do: nil

  defp var_name({name, _, nil}) when is_atom(name), do: name
  defp var_name(_), do: nil

  defp count_literal({:__block__, _, [n]}) when is_integer(n), do: n
  defp count_literal(n) when is_integer(n), do: n
  defp count_literal(_), do: nil

  defp issue(line) do
    %Issue{
      rule: :prefer_enum_split,
      message:
        "Separate `Enum.take/2` and `Enum.drop/2` on the same enumerable " <>
          "traverse the list twice. Use `Enum.split/2` instead: " <>
          "`{taken, rest} = Enum.split(list, count)`.",
      meta: %{line: line}
    }
  end
end
