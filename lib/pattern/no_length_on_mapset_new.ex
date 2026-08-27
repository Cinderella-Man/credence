defmodule Credence.Pattern.NoLengthOnMapsetNew do
  @moduledoc """
  Detects `length(MapSet.new(arg))` and rewrites it to `MapSet.size(MapSet.new(arg))`.

  ## Why this matters

  LLMs frequently wrap `MapSet.new/1` in `length/1` to count distinct elements.
  `length/1` only accepts lists — passing a `MapSet` raises `ArgumentError` at
  runtime. `MapSet.size/1` returns the same integer count and accepts a `MapSet`.

  ## Why the rewrite is a repair

  `length(MapSet.new(arg))` crashes on every input (`ArgumentError: 1st
  argument: not a list`). `MapSet.size(MapSet.new(arg))` is the correct
  equivalent — it returns the same integer (the number of distinct elements)
  without crashing.

  ## Flagged patterns

      length(MapSet.new(items))

  ## Not flagged

      MapSet.size(MapSet.new(items))   — already the correct form
      length(some_list)                — length on a non-MapSet arg
      MapSet.new(items) |> length()    — piped form (different AST shape)

  ## Bad

      defmodule BadNLOMN do
        def f do
          length(MapSet.new())
        end
      end

  ## Good

      defmodule BadNLOMN do
        def f do
          MapSet.size(MapSet.new())
        end
      end
  """

  use Credence.Pattern.Rule

  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    if mapset_alias_shadowed?(ast), do: [], else: check_unshadowed(ast)
  end

  defp check_unshadowed(ast) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case node do
          {:length, meta, [inner]} ->
            if mapset_new_call?(inner) do
              {node, [build_issue(meta) | issues]}
            else
              {node, issues}
            end

          _ ->
            {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    if mapset_alias_shadowed?(ast), do: [], else: fix_unshadowed(ast)
  end

  defp fix_unshadowed(ast) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:length, _meta, [inner]} = node ->
        if mapset_new_call?(inner) do
          mapset_size_call(inner)
        else
          node
        end

      node ->
        node
    end)
  end

  defp mapset_new_call?({{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, _, _}), do: true
  defp mapset_new_call?(_), do: false

  defp mapset_alias_shadowed?(ast) do
    {_ast, shadowed?} =
      Macro.prewalk(ast, false, fn
        {:alias, _, [{:__aliases__, _, target}, opts]} = node, shadowed?
        when is_list(target) and is_list(opts) ->
          {node, shadowed? or shadows_mapset?(target, alias_as(opts))}

        {:alias, _, [{:__aliases__, _, target}]} = node, shadowed? when is_list(target) ->
          {node, shadowed? or shadows_mapset?(target, nil)}

        node, shadowed? ->
          {node, shadowed?}
      end)

    shadowed?
  end

  defp alias_as(opts) do
    Enum.find_value(opts, fn
      {:as, value} -> value
      {{:__block__, _, [:as]}, value} -> value
      _other -> nil
    end)
  end

  defp shadows_mapset?(target, {:__aliases__, _, [:MapSet]}), do: target != [:MapSet]
  defp shadows_mapset?(target, nil), do: List.last(target) == :MapSet and target != [:MapSet]
  defp shadows_mapset?(_target, _as), do: false

  defp mapset_size_call(inner),
    do: {{:., [], [{:__aliases__, [], [:MapSet]}, :size]}, [], [inner]}

  defp build_issue(meta) do
    %Issue{
      rule: :no_length_on_mapset_new,
      message: message(),
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp message do
    "`length/1` on `MapSet.new/1` raises `ArgumentError` at runtime — " <>
      "`length/1` only accepts lists. Use `MapSet.size/1` instead, which " <>
      "returns the same integer count."
  end
end
