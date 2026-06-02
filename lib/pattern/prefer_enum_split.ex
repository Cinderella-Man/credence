defmodule Credence.Pattern.PreferEnumSplit do
  @moduledoc """
  Performance rule: Detects separate `Enum.take/2` and `Enum.drop/2` calls on
  the same enumerable with the same count. Both traverse the list independently;
  `Enum.split/2` produces both results in a single pass.

  ## Bad

      first_half = Enum.take(sorted, count)
      last_half = Enum.reverse(Enum.drop(sorted, count))

      first = Enum.take(items, n)
      rest = Enum.drop(items, n)

  ## Good

      {first_half, rest} = Enum.split(sorted, count)
      last_half = Enum.reverse(rest)

      {first, rest} = Enum.split(items, n)

  ## Scope

  Flags when ALL of these hold:
  - A bound `Enum.take(source, count)` exists in the same scope.
  - A bound `Enum.drop(source, count)` exists with the same `source` and
    `count` (by variable name or literal value).
  - `Enum.drop` may be wrapped in `Enum.reverse/1`.

  Does NOT flag:
  - `Enum.take` or `Enum.drop` alone.
  - Calls on different enumerables or with different counts.
  - Unbound (non-assignment) calls.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    calls = collect_bound_enum_ops(ast)

    calls
    |> Enum.group_by(fn {source, _op, _count, _bound, _line} -> source end)
    |> Enum.flat_map(fn {_source, group} ->
      takes = Enum.filter(group, fn {_, op, _, _, _} -> op == :take end)
      drops = Enum.filter(group, fn {_, op, _, _, _} -> op == :drop end)

      for t <- takes,
          d <- drops,
          elem(t, 2) == elem(d, 2),
          reduce: [] do
        acc ->
          {_, _, _count_key, _, line} = d

          [
            %Issue{
              rule: :prefer_enum_split,
              message:
                "Separate `Enum.take/2` and `Enum.drop/2` on the same enumerable " <>
                  "traverse the list twice. Use `Enum.split/2` instead: " <>
                  "`{taken, rest} = Enum.split(list, count)`.",
              meta: %{line: line}
            }
            | acc
          ]
      end
    end)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # --- collection ---

  defp collect_bound_enum_ops(ast) do
    {_, acc} =
      Macro.prewalk(ast, [], fn
        {:=, meta, [{bound, _, nil}, rhs]}, acc when is_atom(bound) ->
          case extract_enum_op(rhs) do
            {source, op, count} when source != nil and count != nil ->
              {nil, [{source, op, count, bound, Keyword.get(meta, :line)} | acc]}

            _ ->
              {nil, acc}
          end

        node, acc ->
          {node, acc}
      end)

    acc
  end

  # --- extraction ---

  # Enum.take(source, count)
  defp extract_enum_op({{:., _, [{:__aliases__, _, [:Enum]}, :take]}, _, [source, count]}) do
    {extract_var(source), :take, extract_count(count)}
  end

  # Enum.drop(source, count)
  defp extract_enum_op({{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, _, [source, count]}) do
    {extract_var(source), :drop, extract_count(count)}
  end

  # Enum.reverse(Enum.drop(source, count))
  defp extract_enum_op(
         {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _,
          [{{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, _, [source, count]}]}
       ) do
    {extract_var(source), :drop, extract_count(count)}
  end

  # Piped: source |> Enum.take(count)
  defp extract_enum_op(
         {:|>, _, [source_ast, {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, _, [count]}]}
       ) do
    {extract_var(source_ast), :take, extract_count(count)}
  end

  # Piped: source |> Enum.drop(count)
  defp extract_enum_op(
         {:|>, _, [source_ast, {{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, _, [count]}]}
       ) do
    {extract_var(source_ast), :drop, extract_count(count)}
  end

  defp extract_enum_op(_), do: nil

  defp extract_var({name, _, nil}) when is_atom(name), do: name
  defp extract_var(_), do: nil

  defp extract_count({name, _, nil}) when is_atom(name), do: {:var, name}
  defp extract_count({:__block__, _, [value]}) when is_integer(value), do: {:lit, value}
  defp extract_count(value) when is_integer(value), do: {:lit, value}
  defp extract_count(_), do: nil
end
