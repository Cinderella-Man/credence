defmodule Credence.Pattern.NonGroupedClauses do
  @moduledoc """
  Fixes function clauses that are not grouped together.

  When the same function (name + arity) is defined in multiple places in a
  module with other functions between them, the compiler emits a warning
  (which fails compilation under warnings-as-errors).

  ## Bad

      def foo(1), do: 1
      def bar(x), do: x
      def foo(x), do: x + 1   # not grouped with first foo/1!

  ## Good

      def foo(1), do: 1
      def foo(x), do: x + 1
      def bar(x), do: x
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _, [_, kw]} = node, issues when is_list(kw) ->
          case Credence.RuleHelpers.extract_do_body(kw) do
            {:ok, {:__block__, _, body}} -> {node, issues ++ check_body(body)}
            _ -> {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    issues
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)

    RuleHelpers.patches_from_ast_transform(ast, source, fn input ->
      Macro.postwalk(input, &fix_module_node/1)
    end)
  end

  defp check_body(body) do
    {_, _, _, issues} =
      Enum.reduce(body, {nil, MapSet.new(), MapSet.new(), []}, fn expr,
                                                                  {prev_key, seen, flagged,
                                                                   issues} ->
        case function_key(expr) do
          nil ->
            {previous_key_after_non_function(expr, prev_key), seen, flagged, issues}

          key when key == prev_key ->
            {key, seen, flagged, issues}

          key ->
            if key in seen and key not in flagged do
              {name, arity} = key
              meta = elem(expr, 1)

              issue = %Issue{
                rule: :non_grouped_clauses,
                message:
                  "Clauses of `#{name}/#{arity}` are not grouped together. " <>
                    "Move all clauses to be consecutive.",
                meta: %{line: Keyword.get(meta, :line)}
              }

              {key, seen, MapSet.put(flagged, key), [issue | issues]}
            else
              {key, MapSet.put(seen, key), flagged, issues}
            end
        end
      end)

    Enum.reverse(issues)
  end

  defp fix_module_node({:defmodule, meta, [alias_node, [do: {:__block__, block_meta, body}]]}) do
    new_body = group_clauses(body)
    {:defmodule, meta, [alias_node, [do: {:__block__, block_meta, new_body}]]}
  end

  defp fix_module_node(
         {:defmodule, meta, [alias_node, [{do_tag, {:__block__, block_meta, body}}]]}
       ) do
    new_body = group_clauses(body)
    {:defmodule, meta, [alias_node, [{do_tag, {:__block__, block_meta, new_body}}]]}
  end

  defp fix_module_node(node), do: node

  defp group_clauses(body) do
    indexed = Enum.with_index(body)

    # Phase 1: find stray clause indices
    {_, _, stray_set} =
      Enum.reduce(indexed, {nil, MapSet.new(), MapSet.new()}, fn {expr, idx},
                                                                 {prev_key, seen, strays} ->
        case function_key(expr) do
          nil ->
            {previous_key_after_non_function(expr, prev_key), seen, strays}

          key when key == prev_key ->
            {key, seen, strays}

          key ->
            if key in seen do
              {key, seen, MapSet.put(strays, idx)}
            else
              {key, MapSet.put(seen, key), strays}
            end
        end
      end)

    # Don't move clauses preceded by a module attribute (`@impl true`, `@doc`,
    # etc.) — the attribute would be orphaned. `check/2` still flags them.
    #
    # Also don't move a clause with a MULTI-STATEMENT block body: reordering it
    # leaves stale Sourceror `do`/`end` positions that make `Sourceror.to_string`
    # render the block as a `do:` one-liner, dropping every statement after the
    # first (uncompilable → the whole fix is reverted, losing all the other
    # groupings too). Skipping just those strays lets the safe clauses regroup.
    stray_set =
      stray_set
      |> Enum.reject(fn i ->
        preceded_by_attr?(body, i) or multi_statement_body?(Enum.at(body, i))
      end)
      |> MapSet.new()

    if MapSet.size(stray_set) == 0 do
      body
    else
      # Phase 2: remove strays, grouped by function key
      strays_by_key =
        indexed
        |> Enum.filter(fn {_, idx} -> idx in stray_set end)
        |> Enum.group_by(fn {expr, _} -> function_key(expr) end, fn {expr, _} -> expr end)

      cleaned =
        indexed
        |> Enum.reject(fn {_, idx} -> idx in stray_set end)
        |> Enum.map(fn {expr, _} -> expr end)

      # Phase 3: insert each group of strays after the last existing sibling
      Enum.reduce(strays_by_key, cleaned, fn {key, clauses}, acc ->
        insert_after_last_sibling(acc, key, clauses)
      end)
    end
  end

  # A clause whose do-body is a multi-statement block (`do s1\n s2 end`). Moving
  # such a clause mis-renders under Sourceror (see the reject in group_clauses).
  defp multi_statement_body?({kind, _, args}) when kind in [:def, :defp] and is_list(args) do
    case List.last(args) do
      kw when is_list(kw) -> match?({:__block__, _, [_, _ | _]}, do_body_value(kw))
      _ -> false
    end
  end

  defp multi_statement_body?(_), do: false

  defp do_body_value(kw) do
    Enum.find_value(kw, fn
      {{:__block__, _, [:do]}, value} -> value
      {:do, value} -> value
      _ -> nil
    end)
  end

  defp insert_after_last_sibling(body, key, clauses) do
    last_idx =
      body
      |> Enum.with_index()
      |> Enum.filter(fn {expr, _} -> function_key(expr) == key end)
      |> List.last()
      |> elem(1)

    {before, after_part} = Enum.split(body, last_idx + 1)
    before ++ clauses ++ after_part
  end

  # Require a body (`[head, _body]`): a bodiless head (`def f(a, b)` — a forward
  # declaration for default args / docs) generates no clause and must not be
  # counted toward grouping.
  defp function_key({kind, _, [{:when, _, [{name, _, args} | _]}, _body]})
       when kind in [:def, :defp] and is_atom(name) do
    arity = if is_list(args), do: length(args), else: 0
    {name, arity}
  end

  defp function_key({kind, _, [{name, _, args}, _body]})
       when kind in [:def, :defp] and is_atom(name) do
    arity = if is_list(args), do: length(args), else: 0
    {name, arity}
  end

  defp function_key(_), do: nil

  # Module attributes (@doc, @decorate, @impl ...) attach to the *next*
  # function definition and do not trigger Elixir's grouped-clause warning.
  # Preserve `prev_key` across them so `def foo / @doc / def foo` is still
  # seen as a consecutive group; reset on any other non-function statement.
  defp previous_key_after_non_function({:@, _, _}, prev_key), do: prev_key

  # A module-level binding between clauses may be load-bearing — its value can be
  # used in a later clause's guard (e.g. poison's `max_sig = 1 <<< 53` used via
  # `unquote(max_sig)`). Reordering across it would break compilation, so treat
  # it as group-preserving rather than a separator.
  defp previous_key_after_non_function({:=, _, _}, prev_key), do: prev_key

  defp previous_key_after_non_function(expr, prev_key) do
    # A compile-time construct that defines clauses inside it (`for ... do def
    # ... end`, and other macro blocks) is transparent to grouping: Elixir does
    # not emit the grouped-clauses warning across macro-generated clauses, so a
    # literal clause after such a block is not "ungrouped". Preserve prev_key;
    # reset only on genuine non-clause statements.
    if generates_clauses?(expr), do: prev_key, else: nil
  end

  # True if `expr` contains a nested def/defp (e.g. a `for`/comprehension or
  # macro block that generates function clauses at compile time).
  defp generates_clauses?(expr) do
    {_, found} =
      Macro.prewalk(expr, false, fn
        {dt, _, _} = node, _acc when dt in [:def, :defp] -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  defp preceded_by_attr?(body, idx) do
    idx > 0 and match?({:@, _, _}, Enum.at(body, idx - 1))
  end
end
