defmodule Credence.Semantic.FixFunctionInModuleAttributeInlineUsages do
  @moduledoc """
  Fixes the Elixir compile error raised when an anonymous function stored in a
  module attribute is referenced inside a function body.

  LLMs frequently write:

      @default_clock fn -> System.monotonic_time(:millisecond) end

      def start_link(opts) do
        clock = Keyword.get(opts, :clock, @default_clock)
        {:ok, %{clock: clock}}
      end

  The compiler cannot escape function values into the AST and raises:

      cannot inject attribute @default_clock into function/macro because
      cannot escape #Function<...>

  The fix replaces the `@attr fn ... end` definition with a private helper
  (`defp attr_name(args), do: body`), rewrites `@attr` value references to
  `&attr_name/arity` captures, and rewrites direct `@attr.(args)` calls to
  plain `attr_name(args)` calls.

  Only the provably safe core is rewritten. An attribute is eligible when ALL
  of the following hold (everything else is deliberately left untouched):

    * the source contains exactly one module definition (multi-module files
      would pool attributes across module boundaries);
    * the attribute is assigned exactly once, and the value is a
      single-clause `fn` without guards (guards cannot move inside a def-head
      paren list, and multi-clause fns have no single-`defp` equivalent here);
    * the generated `defp name/arity` does not collide with a `Kernel` /
      `Kernel.SpecialForms` auto-import (e.g. `@node fn -> ... end` would
      produce "imported Kernel.node/0 conflicts with local function");
    * every reference to the attribute sits inside a `def`-like body and
      outside any `quote` block — module-level references such as
      `@other @attr` or `@other @attr.()` are legal compile-time code that
      the rewrite would break;
    * every direct `@attr.(args)` call passes exactly `arity` arguments.

  ## Bad

      defmodule M do
        @default_clock fn -> System.monotonic_time(:millisecond) end

        def start_link(opts) do
          clock = Keyword.get(opts, :clock, @default_clock)
          {:ok, %{clock: clock}}
        end
      end

  ## Good

      defmodule M do
        defp default_clock, do: System.monotonic_time(:millisecond)

        def start_link(opts) do
          clock = Keyword.get(opts, :clock, &default_clock/0)
          {:ok, %{clock: clock}}
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "cannot inject attribute"
  @fn_escape "cannot escape #Function"

  @def_like [:def, :defp, :defmacro, :defmacrop]
  @module_like [:defmodule, :defimpl, :defprotocol]

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
    with {:ok, ast} <- Sourceror.parse_string(source),
         true <- single_module?(ast),
         fn_attrs when fn_attrs != %{} <- safe_fn_attributes(ast) do
      result =
        ast
        |> replace_refs(fn_attrs)
        |> replace_attr_defs(fn_attrs)

      # Backstop: if any eligible attribute definition survived (e.g. it sat
      # in a position the block rewrite does not reach), the references were
      # rewritten to captures of a defp that was never created — bail out.
      if leftover_defs?(result, fn_attrs) do
        source
      else
        Sourceror.to_string(result)
      end
    else
      _ -> source
    end
  end

  defp single_module?(ast) do
    {_ast, count} =
      Macro.prewalk(ast, 0, fn
        {d, _, _} = node, acc when d in @module_like -> {node, acc + 1}
        node, acc -> {node, acc}
      end)

    count == 1
  end

  # Map of attr_name => {fn_ast, arity} for every attribute that is safe to
  # rewrite (see the moduledoc for the eligibility conditions).
  defp safe_fn_attributes(ast) do
    {candidates, assign_counts} = candidate_attrs(ast)

    candidates =
      candidates
      |> Enum.reject(fn {name, {_fn_ast, arity}} ->
        Map.get(assign_counts, name, 0) != 1 or conflicts_with_builtin?(name, arity)
      end)
      |> Map.new()

    total = count_refs(ast, candidates, _prune_quote? = false)

    inside =
      ast
      |> def_bodies()
      |> count_refs(candidates, _prune_quote? = true)

    candidates
    |> Enum.filter(fn {name, _} ->
      %{refs: t_refs, bad: t_bad} = Map.get(total, name, %{refs: 0, bad: 0})
      %{refs: i_refs, bad: i_bad} = Map.get(inside, name, %{refs: 0, bad: 0})

      t_bad == 0 and i_bad == 0 and i_refs > 0 and t_refs == i_refs
    end)
    |> Map.new()
  end

  # Collect `@attr fn ... end` candidates (single-clause, guard-free) plus a
  # count of ALL assignments per attribute name, so reassigned attributes can
  # be excluded.
  defp candidate_attrs(ast) do
    {_ast, acc} =
      Macro.prewalk(ast, {%{}, %{}}, fn
        {:@, _, [{name, _, [value]}]} = node, {cands, counts} when is_atom(name) ->
          counts = Map.update(counts, name, 1, &(&1 + 1))

          cands =
            case value do
              {:fn, _, [{:->, _, [params, _body]}]} = fn_ast when is_list(params) ->
                if Enum.any?(params, &match?({:when, _, _}, &1)) do
                  cands
                else
                  Map.put(cands, name, {fn_ast, length(params)})
                end

              _ ->
                cands
            end

          {node, {cands, counts}}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  defp conflicts_with_builtin?(name, arity) do
    {name, arity} in Kernel.__info__(:functions) or
      {name, arity} in Kernel.__info__(:macros) or
      {name, arity} in Kernel.SpecialForms.__info__(:macros)
  end

  # All def/defp/defmacro/defmacrop subtrees (nested defs stay inside their
  # enclosing subtree — the walk does not descend past a collected node).
  defp def_bodies(ast) do
    {_ast, defs} =
      Macro.prewalk(ast, [], fn
        {d, _, _} = node, acc when d in @def_like -> {nil, [node | acc]}
        node, acc -> {node, acc}
      end)

    defs
  end

  # Count references to candidate attributes: `refs` covers value references
  # and arity-correct `@attr.(args)` calls, `bad` counts arity-mismatched
  # calls. With `prune_quote?`, anything under a `quote` is not counted.
  defp count_refs(node, candidates, prune_quote?) do
    {_ast, acc} =
      Macro.prewalk(node, %{}, fn
        {:quote, _, _} = node, acc ->
          if prune_quote?, do: {nil, acc}, else: {node, acc}

        {{:., _, [{:@, _, [{name, _, nil}]}]}, _, args} = node, acc
        when is_atom(name) and is_list(args) ->
          case Map.fetch(candidates, name) do
            {:ok, {_fn_ast, arity}} ->
              key = if length(args) == arity, do: :refs, else: :bad
              # Descend into the call args only, not the `@attr` target.
              {args, bump(acc, name, key)}

            :error ->
              {node, acc}
          end

        {:@, _, [{name, _, nil}]} = node, acc when is_atom(name) ->
          if Map.has_key?(candidates, name) do
            {nil, bump(acc, name, :refs)}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    acc
  end

  defp bump(acc, name, key) do
    Map.update(acc, name, %{refs: 0, bad: 0} |> Map.update!(key, &(&1 + 1)), fn counts ->
      Map.update!(counts, key, &(&1 + 1))
    end)
  end

  # Rewrite `@attr.(args)` to `attr(args)` and `@attr` value references to
  # `&attr/arity` for eligible attributes.
  defp replace_refs(ast, fn_attrs) do
    Macro.prewalk(ast, fn
      {{:., _, [{:@, _, [{name, _, nil}]}]}, call_meta, args} = node
      when is_atom(name) and is_list(args) ->
        case Map.fetch(fn_attrs, name) do
          {:ok, _} -> {name, call_meta, args}
          :error -> node
        end

      {:@, at_meta, [{name, name_meta, nil}]} = node ->
        case Map.fetch(fn_attrs, name) do
          {:ok, {_fn_ast, arity}} ->
            arity_block = {:__block__, [token: to_string(arity)], [arity]}

            capture_inner =
              {:/, [line: at_meta[:line], column: at_meta[:column]],
               [{name, name_meta, nil}, arity_block]}

            {:&, [line: at_meta[:line], column: at_meta[:column]], [capture_inner]}

          :error ->
            node
        end

      node ->
        node
    end)
  end

  # Replace eligible `@attr fn ... end` definitions (as direct block
  # statements) with `defp attr ..., do: body`.
  defp replace_attr_defs(ast, fn_attrs) do
    Macro.postwalk(ast, fn
      {:__block__, block_meta, children} ->
        children =
          Enum.map(children, fn
            {:@, _, [{name, _, [{:fn, _, _}]}]} = node ->
              case Map.fetch(fn_attrs, name) do
                {:ok, {fn_ast, _arity}} -> build_defp(name, fn_ast)
                :error -> node
              end

            node ->
              node
          end)

        {:__block__, block_meta, children}

      node ->
        node
    end)
  end

  defp leftover_defs?(ast, fn_attrs) do
    {_ast, leftover?} =
      Macro.prewalk(ast, false, fn
        {:@, _, [{name, _, [_value]}]} = node, acc when is_atom(name) ->
          {node, acc or Map.has_key?(fn_attrs, name)}

        node, acc ->
          {node, acc}
      end)

    leftover?
  end

  # Build a `defp name(params), do: body` AST from a single-clause fn. A
  # multi-expression body gets a full `do ... end` block instead of `do:`.
  defp build_defp(name, {:fn, _, [{:->, _, [params, body]}]}) do
    head = if params == [], do: {name, [], nil}, else: {name, [], params}

    if match?({:__block__, _, [_, _ | _]}, body) do
      do_kw = {{:__block__, [], [:do]}, body}
      {:defp, [do: [], end: []], [head, [do_kw]]}
    else
      do_kw = {{:__block__, [format: :keyword], [:do]}, body}
      {:defp, [], [head, [do_kw]]}
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
