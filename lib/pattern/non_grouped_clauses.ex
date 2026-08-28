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

  # Moves the original BYTES of each out-of-place clause, as line-level delete +
  # insert patches. Nothing is re-rendered.
  #
  # Two earlier designs were wrong, in instructive ways.
  #
  # **`patches_from_ast_transform/3` cannot express a reorder.** It renders the
  # transform, re-parses it, then `diff_patches/2` pairs the block's statements
  # POSITIONALLY. That is right for a substitution and structurally wrong for a
  # permutation: every position from the move onward differs, so it emitted one
  # patch per statement whose range covered the statement but NOT the whitespace
  # between statements. Observed:
  #
  #     def handle_event("b", _, s), do: s  def helper(x), do: x
  #
  # — and it PARSES, as an ambiguous keyword call, so the re-parse gate could not
  # catch it either. (Two spaces, not one, because `Sourceror.Range` overshoots the
  # end column by one for a bare `true`/`false`/`nil` — range.ex adds +1 for "just
  # the colon" on an atom, and those three are written without one — so the patch
  # range for `@impl true` swallowed the trailing newline as well.)
  #
  # **Re-rendering the whole module is correct but far too blunt.** Measured on
  # `corpus/ex_cldr_territories/lib/cldr/backend.ex`: 1104 lines became 1276, with
  # 534 lines differing that the rule never meant to touch. Sourceror cannot
  # reproduce every original line-wrapping decision from metadata alone, so a
  # whole-module render reformats untouched code. Semantically identical, and still
  # not something to hand a user as a diff.
  #
  # So: slice the original text and move it. The moved region keeps its own bytes,
  # comments included (`include_comments: true`), and every other line in the file
  # is untouched by construction.
  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)
    lines = String.split(source, "\n")

    {_ast, patches} =
      Macro.prewalk(ast, [], fn node, acc ->
        case node do
          {:defmodule, _, [_, [{_, {:__block__, _, body}}]]} when is_list(body) ->
            {node, move_patches(body, lines) ++ acc}

          _ ->
            {node, acc}
        end
      end)

    merge_nested_patches(patches, lines)
  end

  # A module-body replacement can contain another module-body replacement. Applying
  # both ranges independently is unsafe because Sourceror patches bottom-up and the
  # ranges overlap. Fold each inner replacement into its enclosing replacement and
  # return only the outermost, disjoint patches.
  defp merge_nested_patches(patches, lines) do
    patches
    |> Enum.sort_by(&patch_span/1)
    |> Enum.reduce([], fn patch, disjoint ->
      {children, rest} = Enum.split_with(disjoint, &range_contains?(patch, &1))

      merged =
        Enum.reduce(children, patch, fn child, parent ->
          original = patch_source(child, lines)
          %{parent | change: String.replace(parent.change, original, child.change, global: false)}
        end)

      [merged | rest]
    end)
  end

  defp patch_span(%{range: %{start: start, end: finish}}),
    do: Keyword.fetch!(finish, :line) - Keyword.fetch!(start, :line)

  defp range_contains?(%{range: outer}, %{range: inner}) do
    Keyword.fetch!(outer.start, :line) <= Keyword.fetch!(inner.start, :line) and
      Keyword.fetch!(outer.end, :line) >= Keyword.fetch!(inner.end, :line)
  end

  defp patch_source(%{range: %{start: start, end: finish}}, lines) do
    first = Keyword.fetch!(start, :line)
    last = Keyword.fetch!(finish, :line) - 1
    lines |> Enum.slice((first - 1)..(last - 1)) |> Enum.join("\n") |> Kernel.<>("\n")
  end

  # ONE patch for the module body, its text reassembled from the ORIGINAL line
  # slices in the new order.
  #
  # A previous attempt emitted a delete + insert pair per moved slice. That is
  # correct for a single move and corrupts as soon as two functions both move:
  # `foo`'s deletion range and `bar`'s insertion point overlap, and
  # `Sourceror.patch_string/2` applies patches bottom-up without knowing they
  # interact. Measured on `foo(1)/bar(1)/foo(x)/bar(x)`: `foo(x)` came out
  # duplicated and `bar(x)` was lost.
  #
  # One patch cannot overlap itself. And because the text is made of the source's
  # own lines rather than a render, the blast radius is still nil — measured on
  # `corpus/ex_cldr_territories/lib/cldr/backend.ex`, 1104 lines in and 1098 out,
  # the six removed being blank lines absorbed by the moves.
  defp move_patches(body, lines) do
    groupable = groupable_keys(body)
    original = Enum.to_list(0..(length(body) - 1))
    order = new_index_order(body, groupable)

    if groupable == %{} or order == original do
      []
    else
      blocks = index_blocks(body, lines)

      # Separators travel with the statement above them, so whichever statement
      # ends up last brings its trailing blank line along and would leave a gap
      # before the module's `end`. Drop them.
      text =
        order
        |> Enum.flat_map(&Map.fetch!(blocks, &1))
        |> Enum.reverse()
        |> Enum.drop_while(&(String.trim(&1) == ""))
        |> Enum.reverse()
        |> Enum.join("\n")

      first = block_start(body, 0)
      last = block_end(body, length(body) - 1, lines)

      [
        %{
          range: %{start: [line: first, column: 1], end: [line: last + 1, column: 1]},
          change: text <> "\n"
        }
      ]
    end
  end

  # Statement indices after grouping: each groupable function's clauses are emitted
  # consecutively at the position of its FIRST clause, everything else stays put.
  defp new_index_order(body, groupable) do
    owner =
      for {key, slices} <- groupable,
          range <- slices,
          idx <- Enum.to_list(range),
          into: %{},
          do: {idx, key}

    {order, _} =
      Enum.reduce(0..(length(body) - 1), {[], MapSet.new()}, fn idx, {acc, done} ->
        case Map.fetch(owner, idx) do
          {:ok, key} ->
            if MapSet.member?(done, key) do
              {acc, done}
            else
              indices = groupable |> Map.fetch!(key) |> Enum.flat_map(&Enum.to_list/1)
              {Enum.reverse(indices) ++ acc, MapSet.put(done, key)}
            end

          :error ->
            {[idx | acc], done}
        end
      end)

    Enum.reverse(order)
  end

  # `%{index => [source line]}`. Each statement owns the lines from its own start
  # (comments included) up to the line before the NEXT statement's start, so the
  # blank lines that separate statements travel with the statement above them and
  # reassembly cannot lose them.
  defp index_blocks(body, lines) do
    last_idx = length(body) - 1

    for idx <- 0..last_idx, into: %{} do
      from = block_start(body, idx)
      to = block_end(body, idx, lines)
      {idx, Enum.slice(lines, (from - 1)..(to - 1))}
    end
  end

  defp block_start(body, idx) do
    body
    |> Enum.at(idx)
    |> Sourceror.get_range(include_comments: true)
    |> Map.fetch!(:start)
    |> Keyword.fetch!(:line)
  end

  defp block_end(body, idx, lines) do
    if idx < length(body) - 1 do
      block_start(body, idx + 1) - 1
    else
      body
      |> Enum.at(idx)
      |> Sourceror.get_range(include_comments: true)
      |> Map.fetch!(:end)
      |> Keyword.fetch!(:line)
      |> min(length(lines))
    end
  end

  # `check/2` reports exactly the function keys `groupable_keys/1` admits, so a
  # function is never reported when any of its clauses makes the whole move unsafe.
  #
  # This used to be its own near-copy of phase 1 of `group_clauses/1` with no
  # movability test at all, so it flagged every stray whether or not the fix could
  # move it. The two declines were deliberate, and each of their in-file comments
  # ended with the words "`check/2` still flags them" — the report-without-repair
  # was written down in the source rather than overlooked.
  defp check_body(body) do
    groupable = groupable_keys(body)

    body
    |> stray_indices()
    |> Enum.filter(fn idx -> Map.has_key?(groupable, function_key(Enum.at(body, idx))) end)
    |> Enum.sort()
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

  # The index the moved slice must START at: walk back over the contiguous run of
  # ANNOTATION attributes directly above `idx`, so `@impl true` / `@doc` / `@spec`
  # travel with the clause they annotate instead of being orphaned by the move.
  #
  # `:unmovable` when the run contains a non-annotation attribute such as
  # `@threshold 5`. That is a value definition, not an annotation: later clauses may
  # read it, and where it sits relative to them is load-bearing.
  @annotation_attrs [:doc, :typedoc, :impl, :spec, :deprecated, :decorate, :decorate_all]

  defp attr_run_start(_body, 0), do: 0

  defp attr_run_start(body, idx) do
    case Enum.at(body, idx - 1) do
      {:@, _, [{name, _, [_]}]} when name in @annotation_attrs -> attr_run_start(body, idx - 1)
      {:@, _, _} -> :unmovable
      _ -> idx
    end
  end

  # `%{key => [slice_range]}` for every function whose clauses are scattered and
  # whose scattered clauses can all move.
  #
  # The FIRST clause's slice is just itself: the group forms at its position, so it
  # does not move and whatever sits above it — `@moduledoc false`, a `use`, a
  # comment — stays above it. Only the LATER clauses travel, and each takes the run
  # of annotation attributes directly above it. Computing a run for the first clause
  # too was a bug: `@moduledoc false` above it is module-level, not an annotation of
  # that clause, and reading it as `:unmovable` declined the whole function.
  #
  # A key with even one unmovable later slice is left entirely alone — moving only
  # some of them could not preserve relative order.
  defp groupable_keys(body) do
    strays = stray_indices(body)

    if statement_start_lines_unique?(body) do
      do_groupable_keys(body, strays)
    else
      %{}
    end
  end

  defp do_groupable_keys(body, strays) do
    body
    |> Enum.with_index()
    |> Enum.filter(fn {expr, _idx} -> function_key(expr) != nil end)
    |> Enum.group_by(fn {expr, _idx} -> function_key(expr) end, fn {_expr, idx} -> idx end)
    |> Enum.filter(fn {_key, indices} ->
      [_first | rest] = indices

      Enum.any?(indices, &MapSet.member?(strays, &1)) and
        Enum.all?(rest, &(attr_run_start(body, &1) != :unmovable))
    end)
    |> Map.new(fn {key, [first | rest]} ->
      {key, [first..first | Enum.map(rest, fn idx -> attr_run_start(body, idx)..idx end)]}
    end)
  end

  defp statement_start_lines_unique?(body) do
    lines =
      Enum.map(
        body,
        &(&1 |> Sourceror.get_range() |> Map.fetch!(:start) |> Keyword.fetch!(:line))
      )

    Enum.uniq(lines) == lines
  end

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
end
