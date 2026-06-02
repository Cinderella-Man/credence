defmodule Credence.Pattern.NoTrivialDelegation do
  @moduledoc """
  Detects `defp` functions whose entire body is a direct call to a standard
  library function with the same arguments passed through unchanged.

  These trivial wrappers add no value — the caller can use the standard
  library function directly.

  ## Example

      # Bad
      defp string_length(str), do: String.length(str)

      # Good
      # Call `String.length/1` directly at each call site.

  ## Scope

  Only flags delegations to well-known standard library functions where
  every argument is passed through unchanged (same order, no wrapping).
  Delegations to project-local functions or with argument transformation
  are NOT flagged.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  # Standard library functions that should never be wrapped in a defp.
  # {Module, function_name, arity}
  @stdlib_functions MapSet.new([
                      {String, :length, 1},
                      {String, :graphemes, 1},
                      {String, :codepoints, 1},
                      {String, :split, 1},
                      {String, :split, 2},
                      {String, :trim, 1},
                      {String, :downcase, 1},
                      {String, :upcase, 1},
                      {String, :reverse, 1},
                      {String, :replace, 3},
                      {String, :contains?, 2},
                      {String, :starts_with?, 2},
                      {String, :ends_with?, 2},
                      {String, :to_integer, 1},
                      {String, :to_float, 1},
                      {Enum, :count, 1},
                      {Enum, :count, 2},
                      {Enum, :map, 2},
                      {Enum, :filter, 2},
                      {Enum, :reject, 2},
                      {Enum, :reduce, 3},
                      {Enum, :sum, 1},
                      {Enum, :min, 1},
                      {Enum, :max, 1},
                      {Enum, :sort, 1},
                      {Enum, :sort, 2},
                      {Enum, :sort_by, 2},
                      {Enum, :sort_by, 3},
                      {Enum, :reverse, 1},
                      {Enum, :join, 1},
                      {Enum, :join, 2},
                      {Enum, :any?, 1},
                      {Enum, :any?, 2},
                      {Enum, :all?, 1},
                      {Enum, :all?, 2},
                      {Enum, :member?, 2},
                      {Enum, :at, 2},
                      {Enum, :at, 3},
                      {Enum, :slice, 2},
                      {Enum, :slice, 3},
                      {Enum, :take, 2},
                      {Enum, :drop, 2},
                      {Enum, :flat_map, 2},
                      {Enum, :chunk_every, 2},
                      {Enum, :chunk_every, 4},
                      {Enum, :zip, 1},
                      {Enum, :with_index, 1},
                      {Enum, :uniq, 1},
                      {Enum, :uniq_by, 2},
                      {Enum, :frequencies, 1},
                      {Enum, :group_by, 2},
                      {Enum, :into, 2},
                      {Enum, :into, 3},
                      {List, :flatten, 1},
                      {List, :wrap, 1},
                      {List, :to_tuple, 1},
                      {List, :insert_at, 3},
                      {List, :replace_at, 3},
                      {List, :delete_at, 2},
                      {List, :delete, 2},
                      {List, :keyfind, 4},
                      {Map, :get, 2},
                      {Map, :get, 3},
                      {Map, :put, 3},
                      {Map, :delete, 2},
                      {Map, :merge, 2},
                      {Map, :keys, 1},
                      {Map, :values, 1},
                      {Map, :size, 1},
                      {Map, :has_key?, 2},
                      {Map, :update, 4},
                      {Map, :update!, 3},
                      {MapSet, :new, 0},
                      {MapSet, :new, 1},
                      {MapSet, :put, 2},
                      {MapSet, :member?, 2},
                      {MapSet, :size, 1},
                      {MapSet, :union, 2},
                      {MapSet, :intersection, 2},
                      {MapSet, :difference, 2},
                      {Kernel, :length, 1},
                      {Kernel, :is_atom, 1},
                      {Kernel, :is_binary, 1},
                      {Kernel, :is_integer, 1},
                      {Kernel, :is_float, 1},
                      {Kernel, :is_list, 1},
                      {Kernel, :is_map, 1},
                      {Kernel, :is_nil, 1},
                      {Kernel, :map_size, 1},
                      {Kernel, :tuple_size, 1},
                      {Kernel, :elem, 2},
                      {Kernel, :hd, 1},
                      {Kernel, :tl, 1},
                      {Kernel, :trunc, 1},
                      {Kernel, :round, 1},
                      {Kernel, :abs, 1},
                      {Kernel, :rem, 2},
                      {Kernel, :div, 2},
                      {Integer, :to_string, 1},
                      {Integer, :to_string, 2},
                      {Integer, :parse, 1},
                      {Integer, :gcd, 2},
                      {Float, :to_string, 1},
                      {Float, :parse, 1}
                    ])

  @impl true
  def check(ast, _opts) do
    collect_trivial_delegations(ast)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # ── Collection ─────────────────────────────────────────────────────

  defp collect_trivial_delegations(ast) do
    # First pass: collect all function references (&name/arity) in the AST.
    refs = collect_function_refs(ast)

    {_, issues} =
      Macro.prewalk(ast, [], fn
        {:__block__, _meta, stmts} = node, acc when is_list(stmts) ->
          found = Enum.flat_map(stmts, &check_defp(&1, refs))
          {node, found ++ acc}

        node, acc ->
          {node, check_defp(node, refs) ++ acc}
      end)

    Enum.reverse(issues)
  end

  # Collect all &name/arity capture references in the AST.
  defp collect_function_refs(ast) do
    {_, refs} =
      Macro.prewalk(ast, MapSet.new(), fn
        # &name/arity capture — Sourceror wraps the arity in __block__
        {:&, _, [{:/, _, [{name, _, _}, {:__block__, _, [arity]}]}]} = node, acc
        when is_atom(name) and is_integer(arity) ->
          {node, MapSet.put(acc, {name, arity})}

        # &name/arity capture — standard Elixir AST
        {:&, _, [{:/, _, [{name, _, _}, arity]}]} = node, acc
        when is_atom(name) and is_integer(arity) ->
          {node, MapSet.put(acc, {name, arity})}

        node, acc ->
          {node, acc}
      end)

    refs
  end

  defp check_defp({:defp, meta, [head, body_kw]}, refs) when is_list(body_kw) do
    case extract_do_body(body_kw) do
      nil ->
        []

      body ->
        name = extract_func_name(head)
        args = extract_func_args(head)

        # Skip if the function is used as a capture reference (&name/arity).
        if name != nil and args != nil and not MapSet.member?(refs, {name, length(args)}) and
             trivial_delegation?(name, args, body) do
          {mod, wrapped_name, _arity} = delegation_target(body)

          [
            %Issue{
              rule: :no_trivial_delegation,
              message:
                "Private function `#{name}/#{length(args)}` is a trivial wrapper around " <>
                  "#{inspect(mod)}.#{wrapped_name}/#{length(args)}. " <>
                  "Call the standard library function directly instead.",
              meta: %{line: Keyword.get(meta, :line)}
            }
          ]
        else
          []
        end
    end
  end

  defp check_defp(_, _), do: []

  # ── Detection ──────────────────────────────────────────────────────

  # Unwrap single-expression blocks
  defp unwrap_body({:__block__, _, [inner]}), do: unwrap_body(inner)
  defp unwrap_body(other), do: other

  defp trivial_delegation?(_wrapper_name, wrapper_args, body) do
    body = unwrap_body(body)

    case delegation_target(body) do
      {mod, func_name, arity} ->
        MapSet.member?(@stdlib_functions, {mod, func_name, arity}) and
          arity == length(wrapper_args) and
          args_passthrough?(wrapper_args, body)

      _ ->
        false
    end
  end

  # Kernel functions that are auto-imported and commonly wrapped unnecessarily.
  # These appear as local calls in the AST (e.g., `length(x)` not `Kernel.length(x)`).
  @auto_imported_kernel MapSet.new([
                          {:length, 1},
                          {:is_atom, 1},
                          {:is_binary, 1},
                          {:is_integer, 1},
                          {:is_float, 1},
                          {:is_list, 1},
                          {:is_map, 1},
                          {:is_nil, 1},
                          {:map_size, 1},
                          {:tuple_size, 1},
                          {:elem, 2},
                          {:hd, 1},
                          {:tl, 1},
                          {:trunc, 1},
                          {:round, 1},
                          {:abs, 1},
                          {:rem, 2},
                          {:div, 2}
                        ])

  # Extract the {module, function, arity} from a function call AST node.
  defp delegation_target({{:., _, [{:__aliases__, _, mod_parts}, func_name]}, _, args})
       when is_atom(func_name) and is_list(args) do
    {Module.concat(mod_parts), func_name, length(args)}
  end

  defp delegation_target({{:., _, [remote, func_name]}, _, args})
       when is_atom(func_name) and is_list(args) do
    case remote do
      {:__aliases__, _, mod_parts} -> {Module.concat(mod_parts), func_name, length(args)}
      _ -> nil
    end
  end

  # Auto-imported Kernel function called without module prefix.
  defp delegation_target({func_name, _, args})
       when is_atom(func_name) and is_list(args) do
    arity = length(args)

    if MapSet.member?(@auto_imported_kernel, {func_name, arity}) do
      {Kernel, func_name, arity}
    else
      nil
    end
  end

  defp delegation_target(_), do: nil

  # Check that every argument to the wrapper is passed through unchanged
  # to the wrapped function, in the same order.
  defp args_passthrough?(wrapper_args, body) do
    call_args = extract_call_args(body)

    call_args != nil and length(call_args) == length(wrapper_args) and
      Enum.zip(wrapper_args, call_args)
      |> Enum.all?(fn {w_arg, c_arg} -> same?(w_arg, c_arg) end)
  end

  # Extract call arguments from both remote and local call AST nodes.
  defp extract_call_args({{:., _, [_mod, _func]}, _, args}) when is_list(args), do: args
  defp extract_call_args({_name, _, args}) when is_list(args), do: args
  defp extract_call_args(_), do: nil

  # Two AST nodes refer to the same variable if they have the same name
  # and are both simple variables (not underscore-prefixed).
  defp same?({:_, _, _}, _), do: false
  defp same?(_, {:_, _, _}), do: false

  defp same?({name, _, ctx1}, {name, _, ctx2})
       when is_atom(name) and is_atom(ctx1) and is_atom(ctx2),
       do: true

  defp same?(_, _), do: false

  # ── Helpers ────────────────────────────────────────────────────────

  defp extract_do_body(body_kw) when is_list(body_kw) do
    Enum.find_value(body_kw, fn
      {{:__block__, _, [:do]}, body} -> body
      {:do, body} -> body
      _ -> nil
    end)
  end

  defp extract_do_body(_), do: nil

  defp extract_func_name({:when, _, [{name, _, _} | _]}) when is_atom(name), do: name
  defp extract_func_name({name, _, _}) when is_atom(name), do: name
  defp extract_func_name(_), do: nil

  defp extract_func_args({:when, _, [inner_head, _guard]}),
    do: extract_func_args(inner_head)

  defp extract_func_args({_, _, args}) when is_list(args), do: normalize_args(args)
  defp extract_func_args(_), do: nil

  defp normalize_args(args) when is_list(args) do
    Enum.map(args, fn
      {name, meta, ctx} when is_atom(name) and is_atom(ctx) -> {name, meta, ctx}
      other -> other
    end)
  end

  defp normalize_args(_), do: nil
end
