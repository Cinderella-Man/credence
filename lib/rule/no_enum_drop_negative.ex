defmodule Credence.Rule.NoEnumDropNegative do
  @moduledoc """
  Performance rule: Detects `Enum.drop(list, -n)` where `n` is a positive
  integer literal.

  For linked lists, `Enum.drop(list, -n)` must traverse to the end of the
  list to figure out where to cut, making it O(n). This often indicates
  the algorithm should be restructured to avoid needing to trim from the
  tail of a linked list.

  The auto-fix replaces `Enum.drop(list, -n)` with `Enum.slice(list, 0..-(n+1)//1)`,
  which has equivalent semantics. If performance is critical, consider
  restructuring to avoid tail-trimming entirely.

  ## Bad

      list |> Enum.drop(-1)

      Enum.drop(list, -3)

  ## Good

      # If building the list yourself, drop the head before reversing:
      [_ | rest] = reversed_list
      Enum.reverse(rest)

      # Or use Enum.slice/2 if you know the desired length:
      Enum.slice(list, 0..-2//1)
  """
  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Direct: Enum.drop(list, -1)
        {{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, meta, [_, {:-, _, [n]}]} = node, issues
        when is_integer(n) and n > 0 ->
          {node, [build_issue(n, meta) | issues]}

        # Piped: list |> Enum.drop(-1)
        {{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, meta, [{:-, _, [n]}]} = node, issues
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
      # Direct: Enum.drop(list, -n)
      {{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, _, [list_arg, second]} = node ->
        case extract_negative(second) do
          {:ok, n} -> enum_slice_call(list_arg, n)
          :error -> node
        end

      # Piped: |> Enum.drop(-n)
      {{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, _, [single]} = node ->
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

  # Enum.slice(list_arg, 0..-(n+1)//1)
  defp enum_slice_call(list_arg, n) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :slice]}, [], [list_arg, build_range(n)]}
  end

  # Enum.slice(0..-(n+1)//1) — for piped usage
  defp enum_slice_piped(n) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :slice]}, [], [build_range(n)]}
  end

  # Builds AST for 0..-(n+1)//1
  # The :..// operator takes three flat args: start, end, step
  defp build_range(n) do
    {:..//, [], [0, -(n + 1), 1]}
  end

  defp build_issue(n, meta) do
    %Issue{
      rule: :no_enum_drop_negative,
      message:
        "`Enum.drop(list, -#{n})` traverses the entire list to drop from the end. " <>
          "Restructure the algorithm to avoid tail-trimming on linked lists, " <>
          "or drop from the head of a reversed list instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
