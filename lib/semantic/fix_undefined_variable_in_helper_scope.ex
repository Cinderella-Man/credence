defmodule Credence.Semantic.FixUndefinedVariableInHelperScope do
  @moduledoc """
  Fixes `undefined variable` errors caused by LLMs referencing caller-scope
  variables in `defp` helpers (Python scoping assumption).

  LLMs frequently write patterns like:

      def handle_call(:forest, _from, state) do
        result = build_node_tree(state.nodes, :root)
        {:reply, result, state}
      end

      defp build_node_tree(nodes, id) do
        ordered_children = Enum.filter(state.order, fn c -> c.parent_id == id end)
        Map.put(node, :children, ordered_children)
      end

  where `state` is a parameter of `handle_call` but referenced inside the
  `defp` without being passed. The compiler emits `undefined variable "state"`.

  The fix extracts each `var.field` access in the helper, adds `field` as a
  parameter to the `defp`, replaces `var.field` with `field` in the body, and
  passes `var.field` at every call site:

      defp build_node_tree(nodes, order, id) do
        ordered_children = Enum.filter(order, fn c -> c.parent_id == id end)
        Map.put(node, :children, ordered_children)
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{severity: :error, message: msg, file: file})
      when is_binary(msg) and is_binary(file) do
    case extract_var_name(msg) do
      nil ->
        false

      var_name ->
        case File.read(file) do
          {:ok, source} -> source_has_helper_scope_pattern?(source, var_name)
          _ -> false
        end
    end
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :fix_undefined_variable_in_helper_scope,
      message: msg,
      meta: %{line: line(position)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    case extract_var_name(msg) do
      nil ->
        source

      var_name ->
        var_atom = String.to_atom(var_name)

        with {:ok, ast} <- Sourceror.parse_string(source) do
          case find_defp_info(ast, var_atom) do
            {:ok, defp_name, fields} ->
              new_ast = rewrite_module(ast, var_atom, defp_name, fields)
              Sourceror.to_string(new_ast)

            :error ->
              source
          end
        else
          _ -> source
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp extract_var_name(msg) do
    case Regex.run(~r/undefined variable "(\w+)"/, msg) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp line({l, _col}) when is_integer(l), do: l
  defp line(l) when is_integer(l), do: l
  defp line(_), do: nil

  # --- Pattern detection -----------------------------------------------------

  defp source_has_helper_scope_pattern?(source, var_name) do
    var_atom = String.to_atom(var_name)

    with {:ok, ast} <- Sourceror.parse_string(source) do
      match?({:ok, _, _}, find_defp_info(ast, var_atom))
    else
      _ -> false
    end
  end

  # Walk the AST looking for a `defp` whose body references `var_atom.field`.
  # Returns `{:ok, function_name, field_list}` or `:error`.
  defp find_defp_info(ast, var_atom) do
    {_ast, result} =
      Macro.prewalk(ast, nil, fn
        {:defp, _, [{name, _, params}, body_kw]} = node, nil when is_list(params) ->
          body = get_body(body_kw)

          case find_field_accesses(body, var_atom) do
            [] -> {node, nil}
            fields -> {node, {:ok, name, Enum.uniq(fields)}}
          end

        node, acc ->
          {node, acc}
      end)

    result || :error
  end

  defp get_body([{{:__block__, _, [:do]}, body}]), do: body
  defp get_body(_), do: nil

  # Collect every `var_atom.field` access (where `field` is an atom) in `ast`.
  defp find_field_accesses(ast, var_atom) do
    {_ast, fields} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{^var_atom, _, nil}, field]}, _, []} = node, acc
        when is_atom(field) ->
          {node, [field | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(fields)
  end

  # --- AST rewriting ---------------------------------------------------------

  # Top-level entry: walk the module body, rewrite the target defp and every
  # call site that is *not* inside that defp.
  defp rewrite_module({:defmodule, mod_meta, [alias, body_kw]}, var_atom, defp_name, fields) do
    [do_block] = body_kw
    {{:__block__, do_meta, [:do]}, {:__block__, block_meta, stmts}} = do_block

    new_stmts =
      Enum.map(stmts, fn stmt ->
        if is_defp?(stmt, defp_name) do
          rewrite_defp(stmt, var_atom, fields)
        else
          rewrite_calls_in_node(stmt, defp_name, var_atom, fields)
        end
      end)

    new_body_kw = [{{:__block__, do_meta, [:do]}, {:__block__, block_meta, new_stmts}}]
    {:defmodule, mod_meta, [alias, new_body_kw]}
  end

  defp is_defp?({:defp, _, [{name, _, _}, _]}, name), do: true
  defp is_defp?(_, _), do: false

  # Add `field` parameters to the defp and replace `var.field` → `field` in
  # its body.  Also rewrites any recursive calls inside the body.
  defp rewrite_defp({:defp, defp_meta, [{name, name_meta, params}, body_kw]}, var_atom, fields) do
    param_names = Enum.map(params, fn {n, _, _} -> n end)
    new_fields = Enum.reject(fields, fn f -> f in param_names end)
    new_field_params = Enum.map(new_fields, fn f -> {f, [], nil} end)

    new_params =
      case params do
        [] ->
          new_field_params

        _ ->
          {init, [last]} = Enum.split(params, length(params) - 1)
          init ++ new_field_params ++ [last]
      end

    [{{:__block__, do_meta, [:do]}, body}] = body_kw
    new_body = rewrite_body(body, var_atom, name, fields)
    new_body_kw = [{{:__block__, do_meta, [:do]}, new_body}]

    {:defp, defp_meta, [{name, name_meta, new_params}, new_body_kw]}
  end

  # Inside a defp body: replace field accesses AND add arguments to recursive
  # calls (single pass — Macro.prewalk visits children after the parent, so a
  # replaced field access that was an argument to a recursive call is already
  # `field` by the time the call node's children are visited).
  defp rewrite_body(ast, var_atom, defp_name, fields) do
    field_set = MapSet.new(fields)

    Macro.prewalk(ast, fn
      # Replace `var.field` with `field`
      {{:., _, [{^var_atom, _, nil}, field]}, _, []} = node when is_atom(field) ->
        if MapSet.member?(field_set, field), do: {field, [], nil}, else: node

      # Add arguments to recursive calls
      {^defp_name, call_meta, args} when is_list(args) ->
        new_field_args = make_field_args(var_atom, fields)

        case args do
          [] -> {defp_name, call_meta, new_field_args}
          _ -> insert_before_last(args, call_meta, defp_name, new_field_args)
        end

      node ->
        node
    end)
  end

  # Walk any AST node and add `var.field` arguments to every call to
  # `defp_name`.
  defp rewrite_calls_in_node(ast, defp_name, var_atom, fields) do
    Macro.prewalk(ast, fn
      {^defp_name, call_meta, args} when is_list(args) ->
        new_field_args = make_field_args(var_atom, fields)

        case args do
          [] -> {defp_name, call_meta, new_field_args}
          _ -> insert_before_last(args, call_meta, defp_name, new_field_args)
        end

      node ->
        node
    end)
  end

  defp make_field_args(var_atom, fields) do
    Enum.map(fields, fn f ->
      {{:., [], [{var_atom, [], nil}, f]}, [no_parens: true], []}
    end)
  end

  defp insert_before_last(args, meta, name, new_args) do
    {init, [last]} = Enum.split(args, length(args) - 1)
    {name, meta, init ++ new_args ++ [last]}
  end
end
