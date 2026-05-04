defmodule Credence.Rule.NoEnumTakeNegative do
  @moduledoc """
  Performance rule: Detects `Enum.take(list, -n)` where `n` is a positive
  integer literal.

  For linked lists, `Enum.take(list, -n)` must internally determine the list
  length, then traverse again to the cut point — effectively two full
  traversals. If the list was just sorted, sorting in the opposite direction
  and taking a positive count is more efficient.

  The auto-fix replaces `Enum.take(list, -n)` with `Enum.slice(list, -n..-1//1)`,
  which has equivalent semantics and makes the tail-access explicit.

  ## Bad

      sorted = Enum.sort(nums)
      top_three = Enum.take(sorted, -3)

  ## Good

      top_three = Enum.sort(nums, :desc) |> Enum.take(3)

      # Or use Enum.slice/2 to be explicit about the range:
      Enum.slice(sorted, -3..-1//1)
  """
  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Direct: Enum.take(list, -3)
        {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, meta, [_, {:-, _, [n]}]} = node, issues
        when is_integer(n) and n > 0 ->
          {node, [build_issue(n, meta) | issues]}

        # Piped: list |> Enum.take(-3)
        {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, meta, [{:-, _, [n]}]} = node, issues
        when is_integer(n) and n > 0 ->
          {node, [build_issue(n, meta) | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      # Direct: Enum.take(list, -n)
      {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, _, [list_arg, second]} = node ->
        case extract_negative(second) do
          {:ok, n} -> enum_slice_call(list_arg, n)
          :error -> node
        end

      # Piped: |> Enum.take(-n)
      {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, _, [single]} = node ->
        case extract_negative(single) do
          {:ok, n} -> enum_slice_piped(n)
          :error -> node
        end

      node ->
        node
    end)
    |> Sourceror.to_string()
  end

  # Sourceror wraps literals in {:__block__, meta, [value]}, so -1 becomes:
  #   {:-, meta, [{:__block__, meta, [1]}]}
  # Code.string_to_quoted produces the simpler:
  #   {:-, meta, [1]}
  # We handle both, plus a bare negative integer just in case.
  defp extract_negative({:-, _, [{:__block__, _, [n]}]}) when is_integer(n) and n > 0,
    do: {:ok, n}

  defp extract_negative({:-, _, [n]}) when is_integer(n) and n > 0,
    do: {:ok, n}

  defp extract_negative(n) when is_integer(n) and n < 0,
    do: {:ok, abs(n)}

  defp extract_negative(_), do: :error

  # Enum.slice(list_arg, -n..-1//1)
  defp enum_slice_call(list_arg, n) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :slice]}, [], [list_arg, build_range(n)]}
  end

  # Enum.slice(-n..-1//1) — for piped usage
  defp enum_slice_piped(n) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :slice]}, [], [build_range(n)]}
  end

  # Builds AST for -n..-1//1
  # The :..// operator takes three flat args: start, end, step
  defp build_range(n) do
    {:..//, [], [-n, -1, 1]}
  end

  defp build_issue(n, meta) do
    %Issue{
      rule: :no_enum_take_negative,
      message:
        "`Enum.take(list, -#{n})` forces a double traversal of the list to take from the end. " <>
          "Sort in the opposite direction and use `Enum.take(list, #{n})` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
