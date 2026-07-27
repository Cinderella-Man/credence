defmodule Credence.Semantic.FixFunctionInModuleAttributeInlineUsages do
  @moduledoc """
  Fixes the Elixir compiler error when anonymous functions stored in module
  attributes are referenced as values (not called via `@attr.()`).

  LLMs frequently write:

      @default_clock fn -> System.monotonic_time(:millisecond) end

      def start_link(opts) do
        clock = Keyword.get(opts, :clock, @default_clock)
        {:ok, %{clock: clock}}
      end

  The Elixir compiler cannot escape function values into the AST, producing:

      cannot inject attribute @default_clock into function/macro because
      cannot escape #Function<...>

  The fix replaces the `@attr fn -> body end` definition with a private helper
  `defp attr_name, do: body` and converts all `@attr` value references to
  `&attr_name/0` function captures.
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
      rule: :fix_function_in_module_attribute_inline_usages,
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
        has_value_refs? = has_value_references?(ast, fn_attrs)

        if has_value_refs? do
          result =
            ast
            |> replace_value_refs(fn_attrs)
            |> replace_fn_attr_with_defp(fn_attrs)

          if result == ast do
            source
          else
            Sourceror.to_string(result)
          end
        else
          source
        end
      end
    else
      _ -> source
    end
  end

  # Collect all @attr fn ... end definitions, mapping attr_name -> {fn_ast, arity}.
  defp collect_fn_attributes(ast) do
    {_ast, attrs} =
      Macro.prewalk(ast, %{}, fn
        {:@, _meta, [{attr_name, _attr_meta, [{:fn, _, clauses} = fn_ast]}]} = node, acc
        when is_atom(attr_name) ->
          arity = fn_arity_from_clauses(clauses)
          {node, Map.put(acc, attr_name, {fn_ast, arity})}

        node, acc ->
          {node, acc}
      end)

    attrs
  end

  # Determine arity from fn clauses: `fn -> ... end` is arity 0, `fn a, b -> ... end` is arity 2.
  defp fn_arity_from_clauses(clauses) do
    clauses
    |> Enum.map(fn
      {:->, _, [params, _body]} -> length(params)
      _ -> 0
    end)
    |> Enum.max(fn -> 0 end)
  end

  # Check if the AST contains any @attr VALUE references (not @attr.() calls).
  defp has_value_references?(ast, fn_attrs) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        # @attr.() call — NOT a value reference, skip
        {{:., _, [{:@, _, [{attr_name, _, nil}]}]}, _, _}, acc ->
          {nil, acc or Map.has_key?(fn_attrs, attr_name) and false}

        # @attr value reference
        {:@, _, [{attr_name, _, nil}]}, acc ->
          {nil, acc or Map.has_key?(fn_attrs, attr_name)}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # Replace @attr value references (not @attr.() calls) with &attr_name/arity captures.
  defp replace_value_refs(ast, fn_attrs) do
    Macro.prewalk(ast, fn
      # @attr.() call — leave alone (handled by NoFunctionInModuleAttribute)
      {{:., _, [{:@, _, [{attr_name, _, nil}]}]}, _, _} = node ->
        if Map.has_key?(fn_attrs, attr_name), do: node, else: node

      # @attr value reference — replace with &attr_name/arity
      {:@, at_meta, [{attr_name, name_meta, nil}]} = node ->
        case Map.get(fn_attrs, attr_name) do
          {_fn_ast, arity} ->
            # Build &attr_name/arity
            arity_block = {:__block__, [token: to_string(arity)], [arity]}

            capture_inner =
              {:/, [line: at_meta[:line], column: at_meta[:column]],
               [{attr_name, name_meta, nil}, arity_block]}

            {:&, [line: at_meta[:line], column: at_meta[:column]], [capture_inner]}

          nil ->
            node
        end

      node ->
        node
    end)
  end

  # Replace @attr fn -> body end definitions with defp attr_name, do: body.
  defp replace_fn_attr_with_defp(ast, fn_attrs) do
    Macro.postwalk(ast, fn
      {:__block__, block_meta, children} ->
        replaced =
          Enum.map(children, fn
            {:@, _, [{attr_name, _, [{:fn, _, _}]}]} = _attr_node ->
              case Map.get(fn_attrs, attr_name) do
                {fn_ast, _arity} -> build_defp(attr_name, fn_ast)
                nil -> nil
              end

            node ->
              node
          end)
          |> Enum.reject(&is_nil/1)

        case replaced do
          [single] -> single
          _ -> {:__block__, block_meta, replaced}
        end

      node ->
        node
    end)
  end

  # Build a `defp name, do: body` AST from the fn AST.
  defp build_defp(attr_name, {:fn, _, clauses}) do
    case clauses do
      [{:->, _, [[], body]}] ->
        # `fn -> body end` -> `defp name, do: body`
        do_kw = {{:__block__, [format: :keyword], [:do]}, body}
        {:defp, [], [{attr_name, [], nil}, [do_kw]]}

      [{:->, _, [params, body]}] ->
        # `fn a, b -> body end` -> `defp name(a, b), do: body`
        do_kw = {{:__block__, [format: :keyword], [:do]}, body}
        call = {attr_name, [], params}
        {:defp, [], [call, [do_kw]]}

      _ ->
        # Multi-clause fn -> multi-clause defp
        defp_clauses =
          Enum.map(clauses, fn
            {:->, clause_meta, [params, body]} ->
              {{:__block__, [format: :keyword], [:do]}, {:->, clause_meta, [params, body]}}
          end)

        {:defp, [], [{attr_name, [], nil}, defp_clauses]}
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
