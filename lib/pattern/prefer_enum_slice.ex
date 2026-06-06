defmodule Credence.Pattern.PreferEnumSlice do
  @moduledoc """
  Readability rule: flags `Enum.drop/2` followed by `Enum.take/2` and rewrites it
  to `Enum.slice/3`.

  `Enum.drop(list, start) |> Enum.take(len)` keeps elements `[start, start+len)`,
  which is exactly `Enum.slice(list, start, len)` — **but only when both `start`
  and `len` are non-negative**. With a negative `start`, `Enum.drop` counts from
  the end while `Enum.slice`'s start indexes from the end differently; with a
  negative `len`, `Enum.take` keeps the *last* `len` while `Enum.slice` rejects a
  negative length. So the rule fires only when **both amounts are non-negative
  integer literals** — a variable amount could be negative at runtime and is not
  rewritten.

  ## Bad

      Enum.drop(list, 5) |> Enum.take(10)
      Enum.take(Enum.drop(list, 5), 10)

  ## Good

      Enum.slice(list, 5, 10)

  ## Not flagged

      Enum.drop(list, start) |> Enum.take(len)   # variable amounts (could be negative)
      Enum.drop(list, -1) |> Enum.take(2)        # negative drop
      Enum.drop(list, 1) |> Enum.take(-2)        # negative take
  """
  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pattern 1: ... |> Enum.drop(start) |> Enum.take(len)
        {:|>, _,
         [
           {:|>, _, [_left, {{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, _, [drop_amount]}]},
           {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, take_meta, [take_amount]}
         ]} = node,
        issues ->
          maybe_flag(node, drop_amount, take_amount, take_meta, issues)

        # Pattern 2: Enum.take(Enum.drop(list, start), len)
        {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, take_meta,
         [
           {{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, _, [_collection, drop_amount]},
           take_amount
         ]} = node,
        issues ->
          maybe_flag(node, drop_amount, take_amount, take_meta, issues)

        # Pattern 3: Enum.drop(list, start) |> Enum.take(len)
        {:|>, _,
         [
           {{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, _, [_collection, drop_amount]},
           {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, take_meta, [take_amount]}
         ]} = node,
        issues ->
          maybe_flag(node, drop_amount, take_amount, take_meta, issues)

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp maybe_flag(node, drop_amount, take_amount, take_meta, issues) do
    if slice_safe?(drop_amount, take_amount) do
      {node, [build_issue(take_meta) | issues]}
    else
      {node, issues}
    end
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, fn
      # Pattern 1
      {:|>, pipe_meta,
       [
         {:|>, _, [left, {{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, _, [drop_amount]}]},
         {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, _, [take_amount]}
       ]} = node ->
        if slice_safe?(drop_amount, take_amount) do
          {:|>, pipe_meta,
           [left, {{:., [], [{:__aliases__, [], [:Enum]}, :slice]}, [], [drop_amount, take_amount]}]}
        else
          node
        end

      # Pattern 2
      {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, _,
       [
         {{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, _, [collection, drop_amount]},
         take_amount
       ]} = node ->
        if slice_safe?(drop_amount, take_amount) do
          {{:., [], [{:__aliases__, [], [:Enum]}, :slice]}, [], [collection, drop_amount, take_amount]}
        else
          node
        end

      # Pattern 3
      {:|>, _,
       [
         {{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, _, [collection, drop_amount]},
         {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, _, [take_amount]}
       ]} = node ->
        if slice_safe?(drop_amount, take_amount) do
          {{:., [], [{:__aliases__, [], [:Enum]}, :slice]}, [], [collection, drop_amount, take_amount]}
        else
          node
        end

      node ->
        node
    end)
  end

  # Equivalent to Enum.slice/3 only when both amounts are non-negative integer
  # literals. A negative drop/take has different semantics, and a variable could
  # be negative at runtime.
  defp slice_safe?(drop_amount, take_amount),
    do: non_neg_int?(drop_amount) and non_neg_int?(take_amount)

  # Sourceror wraps integer literals as {:__block__, meta, [n]}.
  defp non_neg_int?({:__block__, _, [n]}) when is_integer(n) and n >= 0, do: true
  defp non_neg_int?(n) when is_integer(n) and n >= 0, do: true
  defp non_neg_int?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_enum_slice,
      message:
        "Using `Enum.drop/2` followed by `Enum.take/2` (with non-negative literal " <>
          "counts) is verbose. Use `Enum.slice/3` instead for clearer intent.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
