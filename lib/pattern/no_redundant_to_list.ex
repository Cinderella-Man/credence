defmodule Credence.Pattern.NoRedundantToList do
  @moduledoc """
  Detects `Enum.to_list/1` used before a function that already accepts
  any enumerable, making the conversion a redundant intermediate step.

  `MapSet.new/1` and `Map.new/1` accept enumerables directly, so piping
  through `Enum.to_list/1` first adds an unnecessary list allocation.

  ## Bad

      Enum.to_list(items) |> MapSet.new()
      items |> Enum.to_list() |> MapSet.new()
      MapSet.new(Enum.to_list(items))

  ## Good

      MapSet.new(items)
      MapSet.new(items)
      MapSet.new(items)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    shadowed_aliases = shadowed_aliases(ast)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipe form: <to_list> |> Module.func()  (no extra args — arity-1 after pipe)
        {:|>, meta, [left, {{:., _, [{:__aliases__, _, [module]}, func]}, _, []}]} = node, acc
        when func == :new and module in [:MapSet, :Map] ->
          case {standard_modules?(module, shadowed_aliases), extract_to_list_expr(left)} do
            {true, {:ok, _}} ->
              issue = %Issue{
                rule: :no_redundant_to_list,
                message:
                  "`Enum.to_list/1` is redundant when piped into `#{module}.#{func}/1` — " <>
                    "it already accepts any enumerable directly.",
                meta: %{line: Keyword.get(meta, :line)}
              }

              {node, [issue | acc]}

            _ ->
              {node, acc}
          end

        # Non-pipe form: Module.func(Enum.to_list(...), ...)
        {{:., _, [{:__aliases__, _, [module]}, func]}, meta, [first_arg]} = node, acc
        when func == :new and module in [:MapSet, :Map] ->
          case {standard_modules?(module, shadowed_aliases), extract_to_list_expr(first_arg)} do
            {true, {:ok, _}} ->
              issue = %Issue{
                rule: :no_redundant_to_list,
                message:
                  "`Enum.to_list/1` is redundant inside `#{module}.#{func}/1` — " <>
                    "it already accepts any enumerable directly.",
                meta: %{line: Keyword.get(meta, :line)}
              }

              {node, [issue | acc]}

            _ ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    shadowed_aliases = shadowed_aliases(ast)

    {_ast, patches} =
      Macro.prewalk(ast, [], fn
        # Pipe form: <to_list> |> Module.func() → Module.func(expr)
        {:|>, _, [left, {{:., _, [{:__aliases__, _, [module]}, func]}, _, []}]} = node, acc
        when func == :new and module in [:MapSet, :Map] ->
          case {standard_modules?(module, shadowed_aliases), extract_to_list_expr(left)} do
            {true, {:ok, expr}} ->
              range = Sourceror.get_range(node)
              change = "#{module}.#{func}(#{Sourceror.to_string(expr)})"
              {node, [%{range: range, change: change} | acc]}

            _ ->
              {node, acc}
          end

        # Non-pipe form: Module.func(Enum.to_list(expr)) → Module.func(expr)
        {{:., _, [{:__aliases__, _, [module]}, func]}, _, [first_arg]} = node, acc
        when func == :new and module in [:MapSet, :Map] ->
          case {standard_modules?(module, shadowed_aliases), extract_to_list_expr(first_arg)} do
            {true, {:ok, expr}} ->
              range = Sourceror.get_range(first_arg)
              change = Sourceror.to_string(expr)
              {node, [%{range: range, change: change} | acc]}

            _ ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(patches)
  end

  # Enum.to_list(x)
  defp extract_to_list_expr({{:., _, [{:__aliases__, _, [:Enum]}, :to_list]}, _, [expr]}),
    do: {:ok, expr}

  # x |> Enum.to_list()
  defp extract_to_list_expr(
         {:|>, _, [expr, {{:., _, [{:__aliases__, _, [:Enum]}, :to_list]}, _, _}]}
       ),
       do: {:ok, expr}

  defp extract_to_list_expr(_), do: :error

  defp standard_modules?(destination, shadowed_aliases) do
    not MapSet.member?(shadowed_aliases, :Enum) and
      not MapSet.member?(shadowed_aliases, destination)
  end

  defp shadowed_aliases(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:alias, _, [{:__aliases__, _, source}, opts]} = node, aliases when is_list(opts) ->
          target =
            case alias_as(opts) do
              {:__aliases__, _, [name]} -> name
              nil -> List.last(source)
              _ -> nil
            end

          aliases =
            if target in [:Enum, :Map, :MapSet] and source != [target],
              do: MapSet.put(aliases, target),
              else: aliases

          {node, aliases}

        node, aliases ->
          {node, aliases}
      end)

    aliases
  end

  defp alias_as(opts) do
    Enum.find_value(opts, fn
      {:as, value} -> value
      {{:__block__, _, [:as]}, value} -> value
      _ -> nil
    end)
  end
end
