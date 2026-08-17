defmodule Credence.Pattern.NonGroupedClauses do
  @moduledoc """
  Fixes function clauses that are not grouped together.

  When the same function (name + arity) is defined in multiple places in a
  module with other functions between them, the compiler emits a warning
  (which fails compilation under warnings-as-errors).

  ## Bad

      defmodule RouterNGC do
        def foo(1), do: 1
        def bar(x), do: x
        def foo(x), do: x + 1
      end

  ## Good

      defmodule RouterNGC do
        def foo(1), do: 1
        def foo(x), do: x + 1
        def bar(x), do: x
      end
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

  # `check/2` reports exactly the strays `group_clauses/1` will move, because both
  # go through `movable_stray_indices/1`.
  #
  # This used to be its own near-copy of phase 1 of `group_clauses/1` with no
  # movability test at all, so it flagged every stray whether or not the fix could
  # move it. The two declines were deliberate, and each of their in-file comments
  # ended with the words "`check/2` still flags them" — the report-without-repair
  # was written down in the source rather than overlooked.
  defp check_body(body) do
    body
    |> movable_stray_indices()
    |> Enum.uniq_by(&function_key(Enum.at(body, &1)))
    |> Enum.map(&build_issue(body, &1))
  end

  defp build_issue(body, idx) do
    expr = Enum.at(body, idx)
    {name, arity} = function_key(expr)

    %Issue{
      rule: :non_grouped_clauses,
      message:
        "Clauses of `#{name}/#{arity}` are not grouped together. " <>
          "Move all clauses to be consecutive.",
      meta: %{line: Keyword.get(elem(expr, 1), :line)}
    }
  end

  # Every index whose clause is a stray: a clause for a name/arity already seen
  # earlier, with something else in between.
  defp stray_indices(body) do
    {_, _, strays} =
      body
      |> Enum.with_index()
      |> Enum.reduce({nil, MapSet.new(), MapSet.new()}, fn {expr, idx},
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

    strays
  end

  # The single admission decision, in one place, consumed by both callbacks.
  defp movable_stray_indices(body) do
    body |> stray_indices() |> Enum.filter(&movable_stray?(body, &1)) |> Enum.sort()
  end

  defp movable_stray?(body, idx) do
    not preceded_by_attr?(body, idx) and not unsafe_to_move_body?(Enum.at(body, idx))
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

    # One admission decision, shared with `check_body/1`.
    #
    # A stray preceded by a module attribute is skipped — moving the clause alone
    # would orphan its `@impl true`. Moving the attribute run WITH the clause is a
    # real widening and is specified, but it is not done here: attempted, the moved
    # slice keeps the `do:`/`end:` positions it had at its old location and
    # `patches_from_ast_transform/3` renders with a plain `Sourceror.to_string/1`
    # that honours them, so two clauses print onto one line. It needs the
    # layout-metadata strip and its own verification, on the code path docs/17
    # entry 11 records emitting unparseable output three times.
    #
    # A stray with a MULTI-STATEMENT block body is skipped for the same underlying
    # reason: stale `do`/`end` positions make the block render as a `do:`
    # one-liner, dropping every statement after the first — uncompilable, so the
    # whole fix reverts and every other grouping is lost with it.
    #
    # Because `check/2` now shares this predicate, neither case is reported.
    stray_set = body |> movable_stray_indices() |> MapSet.new()

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

  # A clause whose do-body cannot be safely moved/re-rendered by Sourceror:
  #   * a multi-statement block (`do s1\n s2 end`), OR
  #   * a single statement that is itself a `do…end` block construct
  #     (`with`/`case`/`if`/`unless`/`cond`/`for`/`receive`/`try`).
  # In both cases moving the clause leaves stale `do`/`end` positions, so
  # `Sourceror.to_string` renders the body as a `do:` one-liner — for a do-block
  # statement that re-binds the trailing block to `def`, yielding `def/3`
  # (uncompilable, whole fix reverted). Skipping just these strays lets the safe
  # clauses regroup. `check/2` still flags them.
  defp unsafe_to_move_body?({kind, _, args}) when kind in [:def, :defp] and is_list(args) do
    case List.last(args) do
      kw when is_list(kw) ->
        body = do_body_value(kw)
        multi_statement?(body) or do_block_statement?(body)

      _ ->
        false
    end
  end

  defp unsafe_to_move_body?(_), do: false

  defp multi_statement?({:__block__, _, [_, _ | _]}), do: true
  defp multi_statement?(_), do: false

  # A single statement that is itself a `do…end` block construct — its node's
  # last argument is a keyword list carrying a `:do` key.
  defp do_block_statement?({:__block__, _, [inner]}), do: do_block_statement?(inner)

  defp do_block_statement?({_form, _meta, args}) when is_list(args) and args != [] do
    case List.last(args) do
      kw when is_list(kw) ->
        Enum.any?(kw, fn
          {{:__block__, _, [:do]}, _} -> true
          {:do, _} -> true
          _ -> false
        end)

      _ ->
        false
    end
  end

  defp do_block_statement?(_), do: false

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

  # A directive (`require`/`import`/`alias`) between clauses does NOT trigger
  # Elixir's grouped-clauses warning — the clauses compile warning-free — so it
  # must be transparent to grouping (preserve `prev_key`), not a separator.
  defp previous_key_after_non_function({directive, _, _}, prev_key)
       when directive in [:require, :import, :alias],
       do: prev_key

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
