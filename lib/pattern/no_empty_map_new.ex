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
  """

  use Credence.Pattern.Rule

  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    issues = walk_and_collect(ast, [])
    Enum.reverse(issues)
  end

  # Walk the AST manually to avoid visiting the RHS of `|> Map.new()`.
  defp walk_and_collect({:|>, _, [left, _rhs]}, issues) do
    # The pipe provides the first argument to the RHS function call.
    # Only walk the left side — the RHS `Map.new()` is not standalone.
    walk_and_collect(left, issues)
  end

  defp walk_and_collect(node, issues) when is_tuple(node) and tuple_size(node) == 3 do
    {_form, _meta, args} = node

    issues =
      case check_node(node) do
        {:ok, issue} -> [issue | issues]
        :error -> issues
      end

    if is_list(args) do
      Enum.reduce(args, issues, &walk_and_collect/2)
    else
      issues
    end
  end

  # 2-tuples (e.g. keyword pairs like {:do, body})
  defp walk_and_collect({a, b}, issues) do
    walk_and_collect(a, issues) |> then(&walk_and_collect(b, &1))
  end

  defp walk_and_collect(node, issues) when is_list(node) do
    Enum.reduce(node, issues, &walk_and_collect/2)
  end

  defp walk_and_collect(_, issues), do: issues

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.get(opts, :source, "")

    # Collect byte-range patches manually, skipping Map.new() inside pipe RHS.
    collect_patches(ast, source)
  end

  defp collect_patches(ast, source) do
    patches = walk_patches(ast, source, [])
    Enum.reverse(patches)
  end

  defp walk_patches({:|>, _, [left, _rhs]}, source, patches) do
    # Pipe RHS: skip _rhs (Map.new() there is not standalone).
    walk_patches(left, source, patches)
  end

  defp walk_patches(node, source, patches) when is_tuple(node) and tuple_size(node) == 3 do
    {_form, _meta, args} = node

    patches =
      case check_node(node) do
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
      Enum.reduce(args, patches, &walk_patches(&1, source, &2))
    else
      patches
    end
  end

  defp walk_patches({a, b}, source, patches) do
    walk_patches(a, source, patches) |> then(&walk_patches(b, source, &1))
  end

  defp walk_patches(node, source, patches) when is_list(node) do
    Enum.reduce(node, patches, &walk_patches(&1, source, &2))
  end

  defp walk_patches(_, _source, patches), do: patches

  # ── check helpers ────────────────────────────────────────────────

  defp check_node(
         {{:., meta, [{:__aliases__, _, [:Map]}, :new]}, _, []}
       ) do
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
