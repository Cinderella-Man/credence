defmodule Credence.Pattern.PreferStringSplitTrim do
  @moduledoc """
  Detects `String.split/2` followed by `Enum.filter/2` that removes empty strings,
  which can be replaced with the `:trim` option on `String.split/3`.

  ## Bad

      sentence
      |> String.split(~r/\s+/)
      |> Enum.filter(&(&1 != ""))

  ## Good

      sentence
      |> String.split(~r/\s+/, trim: true)
  """
  use Credence.Pattern.Rule
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:|>, _, _} = node, acc ->
          case find_pattern(node) do
            {:ok, line} ->
              {node,
               [
                 %Issue{
                   rule: :prefer_string_split_trim,
                   message:
                     "`String.split` followed by `Enum.filter` to remove empty strings can be replaced with the `:trim` option.",
                   meta: %{line: line}
                 }
                 | acc
               ]}

            :no ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, &fix_node/1)
  end

  defp fix_node({:|>, _, _} = node) do
    case fix_pipe(node) do
      {:ok, new_ast} -> new_ast
      :no -> node
    end
  end

  defp fix_node(node), do: node

  # Look for: ... |> String.split(regex) |> Enum.filter(&(&1 != ""))
  defp find_pattern({:|>, _, [left, filter_call]}) do
    with true <- empty_filter_call?(filter_call),
         {:|>, pipe_meta, [_prev, split_call]} <- left,
         true <- is_tuple(split_call),
         true <- string_split_call_no_options?(split_call) do
      {:ok, pipe_meta[:line]}
    else
      _ -> :no
    end
  end

  defp find_pattern(_), do: :no

  defp fix_pipe({:|>, _, [left, filter_call]}) do
    with true <- empty_filter_call?(filter_call),
         {:|>, _, [prev, split_call]} <- left,
         true <- is_tuple(split_call),
         true <- string_split_call_no_options?(split_call) do
      {{:., d_meta, [{:__aliases__, a_meta, [:String]}, :split]}, c_meta, [regex]} = split_call

      new_split =
        {{:., d_meta, [{:__aliases__, a_meta, [:String]}, :split]}, c_meta, [regex, [trim: true]]}

      {:ok, {:|>, [], [prev, new_split]}}
    else
      _ -> :no
    end
  end

  defp fix_pipe(_), do: :no

  # Matches Enum.filter(&(&1 != "")) or Enum.filter(&("" != &1))
  defp empty_filter_call?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :filter]}, _, [{:&, _, [{:!=, _, [a, b]}]}]}
       ) do
    capture1? = match?({:&, _, [1]}, a) or match?({:&, _, [{:__block__, _, [1]}]}, a)
    capture2? = match?({:&, _, [1]}, b) or match?({:&, _, [{:__block__, _, [1]}]}, b)
    empty1? = match?({:__block__, _, [""]}, a)
    empty2? = match?({:__block__, _, [""]}, b)

    (capture1? and empty2?) or (capture2? and empty1?)
  end

  defp empty_filter_call?(_), do: false

  # String.split with exactly one arg (no options)
  defp string_split_call_no_options?({{:., _, [{:__aliases__, _, [:String]}, :split]}, _, [_]}),
    do: true

  defp string_split_call_no_options?(_), do: false
end
