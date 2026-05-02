defmodule Credence.Rule.NoRepeatedEnumTraversal do
  @behaviour Credence.Rule
  alias Credence.Issue

  @enum_traversals [
    :count,
    :max,
    :min,
    :sum,
    :member?,
    :any?,
    :all?,
    :find,
    :find_value
  ]

  @impl true
  def check(ast, _opts) do
    {_ast, state} =
      Macro.prewalk(ast, %{}, fn
        {{:., _, [{:__aliases__, _, [:Enum]}, func]}, meta, [arg | _rest]} = node, acc
        when func in @enum_traversals ->
          case var_name(arg) do
            nil ->
              {node, acc}

            var ->
              acc =
                Map.update(acc, var, [{func, meta}], fn existing ->
                  [{func, meta} | existing]
                end)

              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    state
    |> Enum.filter(fn {_var, calls} -> length(calls) > 1 end)
    |> Enum.flat_map(fn {var, calls} ->
      Enum.map(calls, fn {func, meta} ->
        %Issue{
          rule: :no_repeated_enum_traversal,
          message:
            "Repeated traversal of `#{var}` using Enum.#{func}/#{arity(func)}. " <>
              "Consider combining traversals into a single Enum.reduce/3 or caching results.",
          meta: %{line: Keyword.get(meta, :line)}
        }
      end)
    end)
  end

  defp var_name({name, _, context}) when is_atom(name) and is_atom(context), do: name
  defp var_name(_), do: nil

  # Optional: nicer message (not strictly needed)
  defp arity(func) do
    case func do
      f when f in [:member?, :find, :find_value] -> 2
      _ -> 1
    end
  end
end
