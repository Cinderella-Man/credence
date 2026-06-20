defmodule Credence.Pattern.NoRedundantUnderscoreBind do
  @moduledoc """
  Detects `_ = var` bindings in **pattern position** (function heads, `case`/`fn`
  clause heads, `with`/`for` generators) and simplifies them to just `var`.

  In pattern position `_ = var` matches anything and binds it to `var`, which is
  identical to just `var` — the underscore adds no value.

  ## Bad

      def foo(_ = x), do: x + 1

  ## Good

      def foo(x), do: x + 1

  ## Not flagged — statement position

  A standalone `_ = var` in a block body is NOT redundant: it is the idiom
  Elixir's own warning recommends to consume a bound-but-unused value without the
  "variable has no effect / is never returned" warning (NimbleParsec- and
  macro-generated code rely on it). Rewriting it to a bare `var` statement
  reintroduces exactly that warning, so we only fire in pattern position.
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    pattern_binds = pattern_bind_positions(ast)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:=, meta, [{:_, _, nil}, {name, _, ctx}]} = node, acc
        when is_atom(name) and is_atom(ctx) ->
          if MapSet.member?(pattern_binds, position(meta)) do
            {node, [build_issue(meta) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    pattern_binds = pattern_bind_positions(ast)

    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:=, meta, [{:_, _, nil}, {name, _, ctx}]} = node
      when is_atom(name) and is_atom(ctx) ->
        if MapSet.member?(pattern_binds, position(meta)) do
          # Replace _ = var with just var
          elem(node, 2) |> List.last()
        else
          node
        end

      node ->
        node
    end)
  end

  # Positions of `_ = var` nodes that sit in genuine PATTERN position, where
  # `_ = x` is exactly equivalent to `x`: function-head arguments, `->` clause
  # heads (case/fn/with/cond/receive/rescue), and `<-` generators (with/for).
  # A `_ = var` anywhere else is a statement-position discard (see moduledoc) and
  # must be left alone.
  defp pattern_bind_positions(ast) do
    {_ast, set} =
      Macro.prewalk(ast, MapSet.new(), fn
        {dt, _, [{:when, _, [{fn_name, _, args} | _]} | _]} = node, acc
        when dt in [:def, :defp, :defmacro, :defmacrop] and is_atom(fn_name) and is_list(args) ->
          {node, collect_binds(args, acc)}

        {dt, _, [{fn_name, _, args} | _]} = node, acc
        when dt in [:def, :defp, :defmacro, :defmacrop] and is_atom(fn_name) and is_list(args) ->
          {node, collect_binds(args, acc)}

        {:->, _, [patterns, _body]} = node, acc when is_list(patterns) ->
          {node, collect_binds(patterns, acc)}

        {:<-, _, [pattern, _expr]} = node, acc ->
          {node, collect_binds(pattern, acc)}

        node, acc ->
          {node, acc}
      end)

    set
  end

  defp collect_binds(pattern_ast, acc) do
    {_ast, set} =
      Macro.prewalk(pattern_ast, acc, fn
        {:=, meta, [{:_, _, nil}, {name, _, ctx}]} = node, a
        when is_atom(name) and is_atom(ctx) ->
          {node, MapSet.put(a, position(meta))}

        node, a ->
          {node, a}
      end)

    set
  end

  defp position(meta), do: {Keyword.get(meta, :line), Keyword.get(meta, :column)}

  defp build_issue(meta) do
    %Issue{
      rule: :no_redundant_underscore_bind,
      message: "Redundant `_ = var` binding. Use just the variable name instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
