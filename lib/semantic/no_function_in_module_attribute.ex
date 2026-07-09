defmodule Credence.Semantic.NoFunctionInModuleAttribute do
  @moduledoc """
  Fixes the Elixir compiler error when anonymous functions are stored in
  module attributes and called from function bodies.

  LLMs frequently write:

      @default fn -> System.monotonic_time(:millisecond) end
      def now, do: @default.()

  The Elixir compiler cannot escape function values into the AST, producing:

      cannot inject attribute @default into function/macro because cannot escape #Function<...>

  The fix inlines the anonymous function at each `@attr.()` reference site
  and removes the (now-unused) attribute definition:

      def now, do: (fn -> System.monotonic_time(:millisecond) end).()
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "cannot inject attribute"
  @fn_escape "cannot escape #Function"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg) and String.contains?(msg, @fn_escape)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_function_in_module_attribute,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      fn_attrs = collect_fn_attributes(ast)

      if fn_attrs == %{} do
        source
      else
        result =
          ast
          |> replace_fn_attr_calls(fn_attrs)
          |> remove_fn_attribute_defs(fn_attrs)

        if result == ast do
          source
        else
          Sourceror.to_string(result)
        end
      end
    else
      _ -> source
    end
  end

  # Collect all @attr fn ... end definitions, mapping attr_name -> fn AST.
  # If an attribute is defined multiple times, the last definition wins
  # (Macro.prewalk visits in document order, Map.put overwrites).
  defp collect_fn_attributes(ast) do
    {_ast, attrs} =
      Macro.prewalk(ast, %{}, fn
        {:@, _meta, [{attr_name, _attr_meta, [{:fn, _, _} = fn_ast]}]} = node, acc
        when is_atom(attr_name) ->
          {node, Map.put(acc, attr_name, fn_ast)}

        node, acc ->
          {node, acc}
      end)

    attrs
  end

  # Replace every @attr.() call with (fn ... end).()
  defp replace_fn_attr_calls(ast, fn_attrs) do
    Macro.prewalk(ast, fn
      {{:., dot_meta, [{:@, _at_meta, [{attr_name, _, nil}]}]}, call_meta, args} = node ->
        case Map.get(fn_attrs, attr_name) do
          nil -> node
          fn_ast -> {{:., dot_meta, [fn_ast]}, call_meta, args}
        end

      node ->
        node
    end)
  end

  # Remove @attr fn ... end definitions from :__block__ children.
  # When a block is reduced to a single child, unwrap it.
  defp remove_fn_attribute_defs(ast, fn_attrs) do
    Macro.postwalk(ast, fn
      {:__block__, block_meta, children} ->
        filtered =
          Enum.reject(children, fn
            {:@, _, [{attr_name, _, [{:fn, _, _}]}]} when is_atom(attr_name) ->
              Map.has_key?(fn_attrs, attr_name)

            _ ->
              false
          end)

        case filtered do
          [single] -> single
          _ -> {:__block__, block_meta, filtered}
        end

      node ->
        node
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
