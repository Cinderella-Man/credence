defmodule Credence.Semantic.NoRedefineBuiltinType do
  @moduledoc """
  Fixes redefinitions of built-in Erlang/Elixir types.

  LLMs frequently define `@type node` when building tree/trie structures, but
  `node/0` is a built-in Erlang type (the Erlang node name). The compiler
  rejects it with a hard error:

      type node/0 is a built-in type and it cannot be redefined

  The fix renames the offending `@type` (and `@typep`) definition and all
  references to that type within other type definitions. For example,
  `@type node` becomes `@type trie_node`, and `@type t :: node` becomes
  `@type t :: trie_node`.  Variable bindings and function parameters with
  the same name are left untouched.

  ## Bad

      defmodule FooNRBT do
        @type node :: atom()
      end

  ## Good

      defmodule FooNRBT do
        @type trie_node :: atom()
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "is a built-in type and it cannot be redefined"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_redefine_builtin_type,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg} = diagnostic) when is_binary(msg) do
    with type_name when is_binary(type_name) <- extract_type_name(msg),
         {:ok, ast} <- Sourceror.parse_string(source),
         target_module when not is_nil(target_module) <- module_at_line(ast, line(diagnostic)),
         atom_name = String.to_atom(type_name),
         replacement <- unused_replacement(target_module, type_name),
         renamed_module <- rename_type_in_ast(target_module, atom_name, replacement),
         new_ast <- replace_node(ast, target_module, renamed_module),
         true <- new_ast != ast do
      Sourceror.to_string(new_ast)
    else
      _ -> source
    end
  end

  def fix(source, _diagnostic), do: source

  defp module_at_line(ast, line) do
    {_ast, modules} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _, _} = node, modules ->
          range = Sourceror.get_range(node)

          start_line = range.start[:line]
          end_line = range.end[:line]

          if start_line <= line and end_line >= line do
            {node, [{end_line - start_line, node} | modules]}
          else
            {node, modules}
          end

        node, modules ->
          {node, modules}
      end)

    modules
    |> Enum.min_by(&elem(&1, 0), fn -> nil end)
    |> case do
      nil -> nil
      {_span, node} -> node
    end
  end

  defp unused_replacement(module_ast, type_name) do
    {_ast, names} =
      Macro.prewalk(module_ast, MapSet.new(), fn
        {:@, _, [{kind, _, [{:"::", _, [{name, _, args}, _]}]}]} = node, names
        when kind in [:type, :typep, :opaque] and is_atom(name) and args in [nil, []] ->
          {node, MapSet.put(names, name)}

        node, names ->
          {node, names}
      end)

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> String.to_atom("trie_#{type_name}")
      suffix -> String.to_atom("trie_#{type_name}_#{suffix}")
    end)
    |> Enum.find(&(not MapSet.member?(names, &1)))
  end

  defp replace_node(ast, target, replacement) do
    Macro.prewalk(ast, fn node -> if node == target, do: replacement, else: node end)
  end

  # Extract the type name from a diagnostic message like
  # "file.ex:2: type node/0 is a built-in type and it cannot be redefined"
  defp extract_type_name(msg) do
    case Regex.run(~r/type (\w+)\/\d+ is a built-in type/, msg) do
      [_, name] -> name
      _ -> nil
    end
  end

  # Walk the AST and rename the built-in type inside @type / @typep definitions
  # and references to it in other type definitions.
  defp rename_type_in_ast(ast, type_name, replacement) do
    rename_rhs = fn rhs ->
      Macro.prewalk(rhs, fn
        {^type_name, meta, nil} -> {replacement, meta, nil}
        node -> node
      end)
    end

    Macro.prewalk(ast, fn
      # @type builtin :: rhs  — rename LHS and RHS
      {:@, attr_meta,
       [{:type, type_meta, [{:"::", op_meta, [{^type_name, lhs_meta, nil}, rhs]}]}]} ->
        {:@, attr_meta,
         [
           {:type, type_meta,
            [{:"::", op_meta, [{replacement, lhs_meta, nil}, rename_rhs.(rhs)]}]}
         ]}

      # @typep builtin :: rhs — rename LHS and RHS
      {:@, attr_meta,
       [{:typep, type_meta, [{:"::", op_meta, [{^type_name, lhs_meta, nil}, rhs]}]}]} ->
        {:@, attr_meta,
         [
           {:typep, type_meta,
            [{:"::", op_meta, [{replacement, lhs_meta, nil}, rename_rhs.(rhs)]}]}
         ]}

      # @type other :: rhs — rename references in RHS if the builtin is referenced
      {:@, attr_meta, [{:type, type_meta, [{:"::", op_meta, [{other, lhs_meta, nil}, rhs]}]}]} =
          node ->
        new_rhs = rename_rhs.(rhs)

        if new_rhs != rhs do
          {:@, attr_meta,
           [{:type, type_meta, [{:"::", op_meta, [{other, lhs_meta, nil}, new_rhs]}]}]}
        else
          node
        end

      # @typep other :: rhs — rename references in RHS if the builtin is referenced
      {:@, attr_meta, [{:typep, type_meta, [{:"::", op_meta, [{other, lhs_meta, nil}, rhs]}]}]} =
          node ->
        new_rhs = rename_rhs.(rhs)

        if new_rhs != rhs do
          {:@, attr_meta,
           [{:typep, type_meta, [{:"::", op_meta, [{other, lhs_meta, nil}, new_rhs]}]}]}
        else
          node
        end

      # Specs and callbacks can also refer to the renamed local type.
      {:@, attr_meta, [{kind, kind_meta, args}]} = node
      when kind in [:spec, :callback, :macrocallback] ->
        new_args = rename_rhs.(args)

        if new_args == args do
          node
        else
          {:@, attr_meta, [{kind, kind_meta, new_args}]}
        end

      node ->
        node
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
