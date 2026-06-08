defmodule Credence.Pattern.NoEnumIntoEmptyMapset do
  @moduledoc """
  Detects `Enum.into/2` and `Enum.into/3` targeting an empty `MapSet.new()`
  and suggests `MapSet.new/1` or `MapSet.new/2` instead.

  ## Why this matters

  `Enum.into(enum, MapSet.new())` and `Enum.into(enum, MapSet.new(), fun)` are
  the generic collectable path for building MapSets.  `MapSet.new/1` and
  `MapSet.new/2` exist specifically for this purpose, are more readable, and
  signal intent clearly.

  LLMs frequently generate the `Enum.into` form because it is the
  general-purpose collector they learn from many examples.  An Elixir
  developer would reach for `MapSet.new` by default.

  ## Flagged patterns

  | Pattern                                        | Suggested replacement          |
  | ---------------------------------------------- | ------------------------------ |
  | `Enum.into(enum, MapSet.new())`                | `MapSet.new(enum)`             |
  | `Enum.into(enum, MapSet.new(), fun)`           | `MapSet.new(enum, fun)`        |
  | `enum \|> Enum.into(MapSet.new())`             | `MapSet.new(enum)`             |
  | `enum \|> Enum.into(MapSet.new(), fun)`        | `MapSet.new(enum, fun)`        |

  Only the bare `MapSet.new()` call with no arguments is targeted.
  `Enum.into(enum, existing_mapset)` where `existing_mapset` is not
  `MapSet.new()` is left alone — it merges into an existing MapSet,
  which `MapSet.new` does not do.
  """

  use Credence.Pattern.Rule

  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case check_node(node) do
          {:ok, issue} -> {node, [issue | issues]}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      # Piped 3-arg: enum |> Enum.into(MapSet.new(), fun) → enum |> MapSet.new(fun)
      {:|>, pipe_meta,
       [
         enum,
         {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, :into]}, call_meta,
          [{{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, _, []}, fun]}
       ]} ->
        {:|>, pipe_meta,
         [
           enum,
           {{:., dot_meta, [{:__aliases__, alias_meta, [:MapSet]}, :new]}, call_meta, [fun]}
         ]}

      # Piped 2-arg: enum |> Enum.into(MapSet.new()) → MapSet.new(enum)
      {:|>, _pipe_meta,
       [
         enum,
         {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, :into]}, call_meta,
          [{{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, _, []}]}
       ]} ->
        {{:., dot_meta, [{:__aliases__, alias_meta, [:MapSet]}, :new]}, call_meta, [enum]}

      # Direct 3-arg: Enum.into(enum, MapSet.new(), fun) → MapSet.new(enum, fun)
      {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, :into]}, call_meta,
       [enum, {{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, _, []}, fun]} ->
        {{:., dot_meta, [{:__aliases__, alias_meta, [:MapSet]}, :new]}, call_meta, [enum, fun]}

      # Direct 2-arg: Enum.into(enum, MapSet.new()) → MapSet.new(enum)
      {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, :into]}, call_meta,
       [enum, {{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, _, []}]} ->
        {{:., dot_meta, [{:__aliases__, alias_meta, [:MapSet]}, :new]}, call_meta, [enum]}

      node ->
        node
    end)
  end

  # ── check helpers ────────────────────────────────────────────────

  defp check_node(
         {:|>, _,
          [
            _enum,
            {{:., meta, [{:__aliases__, _, [:Enum]}, :into]}, _,
             [{{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, _, []} | _]}
          ]}
       ) do
    {:ok, build_issue(meta)}
  end

  defp check_node(
         {{:., meta, [{:__aliases__, _, [:Enum]}, :into]}, _,
          [_enum, {{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, _, []} | _rest]}
       ) do
    {:ok, build_issue(meta)}
  end

  defp check_node(_), do: :error

  defp build_issue(meta) do
    %Issue{
      rule: :no_enum_into_empty_mapset,
      message:
        "`Enum.into/2` targeting `MapSet.new()` can be replaced with `MapSet.new/1` " <>
          "(or `MapSet.new/2` with a transform function). `MapSet.new` is the idiomatic way " <>
          "to construct a MapSet from an enumerable.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
