defmodule Credence.Pattern.PreferMapNew do
  @moduledoc """
  Detects `Enum.into(enum, %{})` and suggests `Map.new(enum)` instead.

  `Enum.into/2` with an empty map literal `%{}` is the generic collectable
  path for building maps. `Map.new/1` exists specifically for this purpose,
  reads as intent ("build a new map from this enumerable") rather than
  mechanism ("push items into an empty collectable"), and is the idiomatic
  Elixir choice.

  ## Bad

      Enum.into(pairs, %{})

      pairs |> Enum.into(%{})

      Enum.zip(keys, vals) |> Enum.into(%{})

  ## Good

      Map.new(pairs)

      Map.new(pairs)

      Enum.zip(keys, vals) |> Map.new()
  """

  use Credence.Pattern.Rule

  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    if shadows_core_module?(ast) do
      []
    else
      {_ast, issues} =
        Macro.prewalk(ast, [], fn node, issues ->
          case check_node(node) do
            {:ok, issue} -> {node, [issue | issues]}
            :error -> {node, issues}
          end
        end)

      Enum.reverse(issues)
    end
  end

  @impl true
  def fix_patches(ast, _opts) do
    if shadows_core_module?(ast) do
      []
    else
      Credence.RuleHelpers.patches_from_postwalk(ast, fn
        # Piped: enum |> Enum.into(%{}) → Map.new(enum)
        {:|>, pipe_meta,
         [
           enum,
           {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, :into]}, call_meta,
            [{:%{}, _, []}]}
         ]} ->
          {:|>, pipe_meta,
           [
             enum,
             {{:., dot_meta, [{:__aliases__, alias_meta, [:Map]}, :new]}, call_meta, []}
           ]}

        # Direct 2-arg: Enum.into(enum, %{}) → Map.new(enum)
        {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, :into]}, call_meta,
         [enum, {:%{}, _, []}]} ->
          {{:., dot_meta, [{:__aliases__, alias_meta, [:Map]}, :new]}, call_meta, [enum]}

        node ->
          node
      end)
    end
  end

  defp shadows_core_module?(ast) do
    {_ast, shadowed?} =
      Macro.prewalk(ast, false, fn
        {:alias, _, args} = node, false -> {node, shadowing_alias?(args)}
        node, acc -> {node, acc}
      end)

    shadowed?
  end

  defp shadowing_alias?([target, opts]) when is_list(opts) do
    case alias_as(opts) do
      nil -> aliases_core_name?(target)
      as -> aliases_core_name?(as)
    end
  end

  defp shadowing_alias?([target]), do: aliases_core_name?(target)
  defp shadowing_alias?(_), do: false

  defp alias_as(opts) do
    Enum.find_value(opts, fn
      {:as, value} -> value
      {{:__block__, _, [:as]}, value} -> value
      _ -> nil
    end)
  end

  defp aliases_core_name?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:__aliases__, _, parts} = node, false -> {node, List.last(parts) in [:Enum, :Map]}
        node, acc -> {node, acc}
      end)

    found?
  end

  # ── check helpers ────────────────────────────────────────────────

  defp check_node(
         {:|>, _,
          [
            _enum,
            {{:., meta, [{:__aliases__, _, [:Enum]}, :into]}, _, [{:%{}, _, []}]}
          ]}
       ) do
    {:ok, build_issue(meta)}
  end

  defp check_node({{:., meta, [{:__aliases__, _, [:Enum]}, :into]}, _, [_enum, {:%{}, _, []}]}) do
    {:ok, build_issue(meta)}
  end

  defp check_node(_), do: :error

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_map_new,
      message:
        "`Enum.into(enum, %{})` can be replaced with `Map.new(enum)` — " <>
          "same semantics, more idiomatic, reads as intent rather than mechanism.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
