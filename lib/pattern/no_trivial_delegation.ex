defmodule Credence.Pattern.NoTrivialDelegation do
  @moduledoc """
  Detects `defp` functions whose entire body is a direct call to a standard
  library function with the same arguments passed through unchanged, and
  inlines the standard library call at every call site, removing the wrapper.

  These trivial wrappers add no value — the caller can use the standard
  library function directly.

  ## Example

      # Bad
      defp string_length(str), do: String.length(str)
      def run(s), do: string_length(s)

      # Good
      def run(s), do: String.length(s)

  ## Scope (the safe core)

  The fix inlines the wrapper at every call site and deletes the definition.
  That is a whole-module transformation, so it only fires when the rewrite is
  provably behaviour-preserving for **every** input:

  - the wrapper is a **single private clause** with that name (no other `def`
    or `defp` of the same name, no extra clauses to dispatch on),
  - it has **no guard** (a guard would change which inputs are accepted),
  - every argument is passed through unchanged, in order, to a well-known
    standard library function of the same arity,
  - the wrapper is **never captured** (`&name/arity`) and its name never
    appears as a bare atom (`:name`, e.g. inside `apply/3`) or as a variable,
  - **every** call site is an explicit call of the exact arity (no piped
    call with an elided argument), and there is at least one such call site.

  Anything outside that core is deliberately left untouched: `check/2` only
  flags what `fix_patches/2` can safely rewrite, so the two always agree.

  The replacement is the wrapper's **own body** with the call-site arguments
  substituted in — so any module alias in scope (and the exact standard
  library function chosen) is reproduced verbatim, never re-derived.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

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

  # Kernel functions that are auto-imported and appear as local calls in the
  # AST (e.g. `length(x)` not `Kernel.length(x)`).
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

  @impl true
  def check(ast, _opts) do
    ast
    |> fixable_wrappers()
    |> Enum.sort_by(& &1.line)
    |> Enum.map(&to_issue/1)
  end

  @impl true
  def fix_patches(ast, opts) do
    case fixable_wrappers(ast) do
      [] ->
        []

      wrappers ->
        source = Keyword.get(opts, :source) || Sourceror.to_string(ast)
        RuleHelpers.patches_from_ast_transform(ast, source, &transform(&1, wrappers))
    end
  end

  # ── Analysis: the safe core ────────────────────────────────────────

  # Returns one entry per private wrapper whose call sites can be safely
  # inlined: %{name, arity, node, template, line}.
  defp fixable_wrappers(ast) do
    clauses = collect_clauses(ast)
    counts = Enum.frequencies_by(clauses, & &1.name)

    Enum.flat_map(clauses, fn clause ->
      with true <- clause.type == :defp,
           true <- clause.guard? == false,
           # The name must denote exactly one def/defp clause anywhere — no
           # sibling clauses to dispatch on, no public twin.
           1 <- Map.get(counts, clause.name),
           %{} = info <- delegation_info(clause.name, clause.args, clause.body),
           true <- safe_to_inline?(ast, clause.name, clause.arity) do
        [
          %{
            name: clause.name,
            arity: clause.arity,
            node: clause.node,
            template: info.template,
            mod: info.mod,
            fun: info.fun,
            line: clause.line
          }
        ]
      else
        _ -> []
      end
    end)
  end

  # Collect every def/defp clause as a flat record.
  defp collect_clauses(ast) do
    {_ast, acc} =
      Macro.prewalk(ast, [], fn
        {dt, meta, [head, body_kw]} = node, acc
        when dt in [:def, :defp] and is_list(body_kw) ->
          name = extract_func_name(head)
          args = extract_func_args(head)
          body = extract_do_body(body_kw)

          # `extract_func_name/1` returns an atom name or `nil`; reject the
          # `nil` sentinel explicitly (`is_atom(nil)` is true, so it would not).
          if name != nil and is_list(args) and body != nil do
            clause = %{
              type: dt,
              name: name,
              arity: length(args),
              args: args,
              guard?: match?({:when, _, _}, head),
              body: body,
              node: node,
              line: Keyword.get(meta, :line)
            }

            {node, [clause | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    acc
  end

  # If the wrapper body is a trivial passthrough to a known stdlib function,
  # return %{mod, fun, template}; otherwise nil. The template is the body
  # call node itself (its arguments get replaced at each call site).
  defp delegation_info(wrapper_name, wrapper_args, body) do
    body = unwrap_body(body)

    case delegation_target(body) do
      {mod, fun, arity} ->
        cond do
          not MapSet.member?(@stdlib_functions, {mod, fun, arity}) -> nil
          arity != length(wrapper_args) -> nil
          not args_passthrough?(wrapper_args, body) -> nil
          # `defp length(l), do: length(l)` is recursion, not delegation:
          # the local name shadows the Kernel import.
          mod == Kernel and local_call?(body) and fun == wrapper_name -> nil
          true -> %{mod: mod, fun: fun, template: body}
        end

      _ ->
        nil
    end
  end

  # Every reference to `name` in the whole AST must be an explicit call of the
  # wrapper's exact arity — never a capture, a bare atom, a variable, or a
  # piped/other-arity call — and there must be at least one real call site.
  defp safe_to_inline?(ast, name, arity) do
    captured? = name in (ast |> collect_function_refs() |> Enum.map(&elem(&1, 0)))

    {call_arities, var?, atom?} = scan_occurrences(ast, name)

    not captured? and not var? and not atom? and
      Enum.all?(call_arities, &(&1 == arity)) and
      length(call_arities) >= 2
  end

  # Walks the AST and classifies every node that mentions `name`:
  #   - call form `{name, _, args}` (def head + call sites + piped uses)
  #   - variable  `{name, _, ctx}` with atom context (includes nil)
  #   - atom literal `{:__block__, _, [name]}` (`:name`, keyword keys, apply/3)
  defp scan_occurrences(ast, name) do
    {_ast, {arities, var?, atom?}} =
      Macro.prewalk(ast, {[], false, false}, fn
        {^name, _, args} = node, {arities, v, a} when is_list(args) ->
          {node, {[length(args) | arities], v, a}}

        {^name, _, ctx} = node, {arities, _v, a} when is_atom(ctx) ->
          {node, {arities, true, a}}

        {:__block__, _, [^name]} = node, {arities, v, _a} ->
          {node, {arities, v, true}}

        node, acc ->
          {node, acc}
      end)

    {arities, var?, atom?}
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

  # ── Transformation ─────────────────────────────────────────────────

  defp transform(ast, wrappers) do
    targets = MapSet.new(wrappers, & &1.node)

    templates =
      Map.new(wrappers, fn w -> {{w.name, w.arity}, clean_meta(w.template)} end)

    ast
    |> drop_wrapper_defs(targets)
    |> rewrite_calls(templates)
  end

  # Remove the wrapper definitions from their enclosing module block.
  defp drop_wrapper_defs(ast, targets) do
    Macro.prewalk(ast, fn
      {:__block__, meta, stmts} when is_list(stmts) ->
        {:__block__, meta, Enum.reject(stmts, &MapSet.member?(targets, &1))}

      node ->
        node
    end)
  end

  # Replace each call `name(args)` with the wrapper body, substituting the
  # call-site arguments into the body's argument slot.
  defp rewrite_calls(ast, templates) do
    Macro.prewalk(ast, fn
      {name, _meta, args} = node when is_atom(name) and is_list(args) ->
        case Map.fetch(templates, {name, length(args)}) do
          {:ok, template} -> put_elem(template, 2, args)
          :error -> node
        end

      node ->
        node
    end)
  end

  # Drop comment metadata so a body reused at several call sites doesn't
  # duplicate the wrapper's own comments.
  defp clean_meta(node) do
    Macro.prewalk(node, fn
      {form, meta, args} when is_list(meta) ->
        {form, Keyword.drop(meta, [:leading_comments, :trailing_comments]), args}

      other ->
        other
    end)
  end

  # ── Detection helpers ──────────────────────────────────────────────

  # Unwrap single-expression blocks.
  defp unwrap_body({:__block__, _, [inner]}), do: unwrap_body(inner)
  defp unwrap_body(other), do: other

  # A local (auto-imported) call has no module qualifier.
  defp local_call?({name, _, args}) when is_atom(name) and is_list(args), do: true
  defp local_call?(_), do: false

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

  # ── Issue + small extractors ───────────────────────────────────────

  defp to_issue(%{name: name, arity: arity, mod: mod, fun: fun, line: line}) do
    %Issue{
      rule: :no_trivial_delegation,
      message:
        "Private function `#{name}/#{arity}` is a trivial wrapper around " <>
          "#{inspect(mod)}.#{fun}/#{arity}. " <>
          "Call the standard library function directly instead.",
      meta: %{line: line}
    }
  end

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

  defp extract_func_args({_, _, args}) when is_list(args), do: args
  defp extract_func_args(_), do: nil
end
