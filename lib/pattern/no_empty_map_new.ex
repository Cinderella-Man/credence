defmodule Credence.Pattern.NoEmptyMapNew do
  @moduledoc """
  Detects `Map.new()` called with no arguments and suggests the empty map
  literal `%{}` instead.

  ## Why this matters

  `Map.new()` with zero arguments returns an empty map, identical to `%{}`.
  The literal `%{}` is the idiomatic Elixir way to express an empty map —
  it is shorter, more recognizable, and what every Elixir developer would
  reach for.

  LLMs sometimes generate `Map.new()` because `Map.new/1` and `Map.new/2`
  are the idiomatic way to build a map from an enumerable.  The zero-argument
  form is a misgeneralization of that pattern.

  ## Flagged patterns

  | Pattern        | Suggested replacement |
  | -------------- | --------------------- |
  | `Map.new()`    | `%{}`                 |

  Only the zero-argument call is targeted.  `Map.new(enum)`, `Map.new(enum, fun)`,
  and piped forms like `enum |> Map.new()` are all idiomatic and left alone.

  ## Bad

      defmodule BadNEMN do
        def build do
          a = Map.new()
          b = Map.new()
          {a, b}
        end
      end

  ## Good

      defmodule BadNEMN do
        def build do
          a = %{}
          b = %{}
          {a, b}
        end
      end
  """

  use Credence.Pattern.Rule

  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {issues, _map_shadowed?} = walk_and_collect(ast, [], false)
    Enum.reverse(issues)
  end

  defp walk_and_collect({:quote, _, _args}, issues, map_shadowed?),
    do: {issues, map_shadowed?}

  defp walk_and_collect({:__block__, _, expressions}, issues, map_shadowed?) do
    Enum.reduce(expressions, {issues, map_shadowed?}, fn expression, {acc, shadowed?} ->
      walk_and_collect(expression, acc, shadowed?)
    end)
  end

  defp walk_and_collect({:alias, _, args}, issues, map_shadowed?) do
    {issues, alias_shadows_map?(args) || map_shadowed?}
  end

  defp walk_and_collect({:|>, _, [left, rhs]}, issues, map_shadowed?) do
    {issues, map_shadowed?} = walk_and_collect(left, issues, map_shadowed?)

    if match?({:ok, _}, check_node(rhs)) do
      {issues, map_shadowed?}
    else
      walk_and_collect(rhs, issues, map_shadowed?)
    end
  end

  # An arity capture `&Mod.fun/arity` (here `&Map.new/0`): the `Map.new`
  # operand is a zero-arg *reference*, AST-identical to a real `Map.new()`
  # call. Rewriting it to `%{}` would yield `&%{}/0`, which does not compile
  # ("invalid args for &"). Don't descend into the capture.
  defp walk_and_collect({:&, _, [{:/, _, [_fun, _arity]}]}, issues, map_shadowed?),
    do: {issues, map_shadowed?}

  defp walk_and_collect(node, issues, map_shadowed?)
       when is_tuple(node) and tuple_size(node) == 3 do
    {_form, _meta, args} = node

    issues =
      case check_node(node) do
        {:ok, _issue} when map_shadowed? -> issues
        {:ok, issue} -> [issue | issues]
        :error -> issues
      end

    if is_list(args) do
      {Enum.reduce(args, issues, fn arg, acc ->
         {acc, _nested_shadowed?} = walk_and_collect(arg, acc, map_shadowed?)
         acc
       end), map_shadowed?}
    else
      {issues, map_shadowed?}
    end
  end

  # 2-tuples (e.g. keyword pairs like {:do, body})
  defp walk_and_collect({a, b}, issues, map_shadowed?) do
    {issues, _} = walk_and_collect(a, issues, map_shadowed?)
    {issues, _} = walk_and_collect(b, issues, map_shadowed?)
    {issues, map_shadowed?}
  end

  defp walk_and_collect(node, issues, map_shadowed?) when is_list(node) do
    {Enum.reduce(node, issues, fn child, acc ->
       {acc, _} = walk_and_collect(child, acc, map_shadowed?)
       acc
     end), map_shadowed?}
  end

  defp walk_and_collect(_, issues, map_shadowed?), do: {issues, map_shadowed?}

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.get(opts, :source, "")

    # Collect byte-range patches manually, skipping Map.new() inside pipe RHS.
    collect_patches(ast, source)
  end

  defp collect_patches(ast, source) do
    {patches, _map_shadowed?} = walk_patches(ast, source, [], false)
    Enum.reverse(patches)
  end

  defp walk_patches({:quote, _, _args}, _source, patches, map_shadowed?),
    do: {patches, map_shadowed?}

  defp walk_patches({:__block__, _, expressions}, source, patches, map_shadowed?) do
    Enum.reduce(expressions, {patches, map_shadowed?}, fn expression, {acc, shadowed?} ->
      walk_patches(expression, source, acc, shadowed?)
    end)
  end

  defp walk_patches({:alias, _, args}, _source, patches, map_shadowed?) do
    {patches, alias_shadows_map?(args) || map_shadowed?}
  end

  defp walk_patches({:|>, _, [left, rhs]}, source, patches, map_shadowed?) do
    {patches, map_shadowed?} = walk_patches(left, source, patches, map_shadowed?)

    if match?({:ok, _}, check_node(rhs)) do
      {patches, map_shadowed?}
    else
      walk_patches(rhs, source, patches, map_shadowed?)
    end
  end

  # Arity capture `&Map.new/0`: see `walk_and_collect/2` — never rewrite.
  defp walk_patches({:&, _, [{:/, _, [_fun, _arity]}]}, _source, patches, map_shadowed?),
    do: {patches, map_shadowed?}

  defp walk_patches(node, source, patches, map_shadowed?)
       when is_tuple(node) and tuple_size(node) == 3 do
    {_form, _meta, args} = node

    patches =
      case check_node(node) do
        {:ok, _issue} when map_shadowed? ->
          patches

        {:ok, _issue} ->
          case Sourceror.get_range(node) do
            %Sourceror.Range{} = range ->
              [%{range: range, change: "%{}"} | patches]

            _ ->
              patches
          end

        :error ->
          patches
      end

    if is_list(args) do
      {Enum.reduce(args, patches, fn arg, acc ->
         {acc, _nested_shadowed?} = walk_patches(arg, source, acc, map_shadowed?)
         acc
       end), map_shadowed?}
    else
      {patches, map_shadowed?}
    end
  end

  defp walk_patches({a, b}, source, patches, map_shadowed?) do
    {patches, _} = walk_patches(a, source, patches, map_shadowed?)
    {patches, _} = walk_patches(b, source, patches, map_shadowed?)
    {patches, map_shadowed?}
  end

  defp walk_patches(node, source, patches, map_shadowed?) when is_list(node) do
    {Enum.reduce(node, patches, fn child, acc ->
       {acc, _} = walk_patches(child, source, acc, map_shadowed?)
       acc
     end), map_shadowed?}
  end

  defp walk_patches(_, _source, patches, map_shadowed?), do: {patches, map_shadowed?}

  defp alias_shadows_map?([
         {:__aliases__, _, target},
         [{{:__block__, _, [:as]}, {:__aliases__, _, [:Map]}}]
       ]),
       do: target not in [[:Map], [:"Elixir", :Map]]

  defp alias_shadows_map?([{:__aliases__, _, target}]) do
    List.last(target) == :Map and target not in [[:Map], [:"Elixir", :Map]]
  end

  defp alias_shadows_map?(_args), do: false

  # ── check helpers ────────────────────────────────────────────────

  defp check_node({{:., meta, [{:__aliases__, _, [:Map]}, :new]}, _, []}) do
    {:ok, build_issue(meta)}
  end

  defp check_node(_), do: :error

  defp build_issue(meta) do
    %Issue{
      rule: :no_empty_map_new,
      message:
        "`Map.new()` with no arguments returns an empty map, identical to `%{}`. " <>
          "Use the empty map literal `%{}` instead — it is shorter and idiomatic.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
