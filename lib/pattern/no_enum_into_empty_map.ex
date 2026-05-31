defmodule Credence.Pattern.NoEnumIntoEmptyMap do
  @moduledoc """
  Detects `Enum.into/2` and `Enum.into/3` targeting an empty map literal `%{}`
  and suggests `Map.new/1` or `Map.new/2` instead.

  ## Why this matters

  `Enum.into(enum, %{})` and `Enum.into(enum, %{}, fun)` are the generic
  collectable path for building maps.  `Map.new/1` and `Map.new/2` exist
  specifically for this purpose, are more readable, and signal intent
  clearly.

  LLMs frequently generate the `Enum.into` form because it is the
  general-purpose collector they learn from many examples.  An Elixir
  developer would reach for `Map.new` by default.

  ## Flagged patterns

  | Pattern                                  | Suggested replacement       |
  | ---------------------------------------- | --------------------------- |
  | `Enum.into(enum, %{})`                   | `Map.new(enum)`             |
  | `Enum.into(enum, %{}, fun)`              | `Map.new(enum, fun)`        |
  | `enum |> Enum.into(%{})`                 | `Map.new(enum)`             |
  | `enum |> Enum.into(%{}, fun)`            | `Map.new(enum, fun)`        |

  Only the empty-map literal `%{}` is targeted.  `Enum.into(enum, existing_map, fun)`
  where `existing_map` is not an empty literal is left alone — it merges
  into an existing map, which `Map.new` does not do.
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
      # Piped 3-arg: enum |> Enum.into(%{}, fun) → enum |> Map.new(fun)
      {:|>, pipe_meta,
       [
         enum,
         {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, :into]}, call_meta,
          [{:%{}, _, []}, fun]}
       ]} ->
        {:|>, pipe_meta,
         [
           enum,
           {{:., dot_meta, [{:__aliases__, alias_meta, [:Map]}, :new]}, call_meta, [fun]}
         ]}

      # Piped 2-arg: enum |> Enum.into(%{}) → Map.new(enum)
      {:|>, _pipe_meta,
       [
         enum,
         {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, :into]}, call_meta,
          [{:%{}, _, []}]}
       ]} ->
        {{:., dot_meta, [{:__aliases__, alias_meta, [:Map]}, :new]}, call_meta, [enum]}

      # Direct 3-arg: Enum.into(enum, %{}, fun) → Map.new(enum, fun)
      {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, :into]}, call_meta,
       [enum, {:%{}, _, []}, fun]} ->
        {{:., dot_meta, [{:__aliases__, alias_meta, [:Map]}, :new]}, call_meta,
         [enum, fun]}

      # Direct 2-arg: Enum.into(enum, %{}) → Map.new(enum)
      {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, :into]}, call_meta,
       [enum, {:%{}, _, []}]} ->
        {{:., dot_meta, [{:__aliases__, alias_meta, [:Map]}, :new]}, call_meta, [enum]}

      node ->
        node
    end)
  end

  # ── check helpers ────────────────────────────────────────────────

  defp check_node(
         {:|>, _,
          [
            _enum,
            {{:., meta, [{:__aliases__, _, [:Enum]}, :into]}, _, [{:%{}, _, []} | _]}
          ]}
       ) do
    {:ok, build_issue(meta)}
  end

  defp check_node(
         {{:., meta, [{:__aliases__, _, [:Enum]}, :into]}, _,
          [_enum, {:%{}, _, []} | _rest]}
       ) do
    {:ok, build_issue(meta)}
  end

  defp check_node(_), do: :error

  defp build_issue(meta) do
    %Issue{
      rule: :no_enum_into_empty_map,
      message:
        "`Enum.into/2` targeting an empty map `%{}` can be replaced with `Map.new/1` " <>
          "(or `Map.new/2` with a transform function). `Map.new` is the idiomatic way " <>
          "to construct a map from an enumerable.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
