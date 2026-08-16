defmodule Credence.Pattern.NoEnumCountForLength do
  @moduledoc """
  Detects `Enum.count/1` (without a predicate) on a **provably-list** argument
  and rewrites it to `length/1`.

  ## Why this matters

  `Enum.count/1` goes through the `Enumerable` protocol, adding dispatch
  overhead. When the argument is a list, `length/1` is a BIF that does the same
  traversal without protocol dispatch:

      # Flagged — argument is provably a list
      total = Map.keys(config) |> Enum.count()

      # Idiomatic — BIF, no protocol overhead
      total = length(Map.keys(config))

  ## The grapheme forms belong to the sibling rules, not to this one

  This example used to be `String.graphemes(text) |> Enum.count()`, and that was
  a bad thing to teach: the rewrite it shows —
  `length(String.graphemes(text))` — still builds the whole grapheme list, which
  is the exact allocation `AvoidGraphemesEnumCount` and `AvoidGraphemesLength`
  exist to remove. Both of those go all the way to `String.length(text)`.

  This rule still *matches* the grapheme form, so the family is convergent
  rather than partitioned, and `test/pattern/graphemes_count_family_test.exs`
  pins that convergence from every entry point: whichever of the three fires
  first, the Pattern round settles on `String.length/1`. Worth knowing why that
  holds, because today it holds for two different reasons — `AvoidGraphemes*`
  happens to sort before `NoEnumCountForLength`, *and* the round is a cascade,
  so even the weaker rewrite is picked up by `AvoidGraphemesLength` on the way
  past. The second reason is the one that survives a rename.

  ## Why "provably a list"

  `length/1` only accepts lists — `length(1..5)` raises `ArgumentError`, while
  `Enum.count(1..5)` returns `5`. So the rewrite is behaviour-preserving **only**
  when the argument is known to be a list. The rule therefore fires only when the
  argument is:

  - a list literal (`[a, b, c]`),
  - a `++` concatenation, or
  - a call (or pipe ending in a call) to a list-returning function —
    `String.graphemes/split/...`, `Map.keys/values`, `Enum.map/filter/sort/...`,
    `List.*`, etc.

  A bare variable (`Enum.count(chars)`) is **not** flagged: its type is unknown,
  and it might be a range, map, or stream rather than a list.

  ## Flagged patterns

  Only the **single-argument** form `Enum.count(x)` (direct or piped). The
  two-argument `Enum.count(x, predicate)` is not flagged (it filters and counts
  in one pass).

  ## Bad

      defmodule BadNECFL do
        def grapheme_count(str) do
          Enum.count(String.graphemes(str))
        end
      end

  ## Good

      defmodule BadNECFL do
        def grapheme_count(str) do
          length(String.graphemes(str))
        end
      end
  """

  use Credence.Pattern.Rule
  # diverges in ash_expr: the fix rewrites the bare expression `Enum.count(<list
  # expr>)` to a BARE local call `length(x)` (or `map_size(m)`) anywhere it
  # appears, and inside `expr(...)` Ash reinterprets bare local calls as
  # expression functions (it has a `length/1`), so the rewrite changes what the
  # macro builds while still compiling — unlike its six siblings here, which
  # only ever emit qualified `Enum.*`/`List.*`/`Map.*` calls. Ecto/Nx are
  # omitted because `Enum.count/1` and `length/1` are both compile errors in a
  # query expression / defn body, so the rule only ever touches code already
  # broken there. The one check that would settle it: confirm
  # `Ash.Query.Function.Length` (bare `length/1` inside `expr`) exists in the
  # targeted Ash version — I could not verify it offline (no `ash` in deps/, no
  # network)
  @impl true
  def unsafe_in_dsl, do: [:ash_expr]
  alias Credence.Issue

  # Functions whose result is always a list. Keys are the AST alias atoms.
  @list_returning %{
    Enum: ~w(map filter reject to_list sort sort_by uniq uniq_by reverse take drop
         take_while drop_while flat_map with_index dedup dedup_by concat
         intersperse chunk_every chunk_by slice map_every scan)a,
    String: ~w(graphemes codepoints split to_charlist)a,
    Map: ~w(keys values to_list)a,
    Keyword: ~w(keys values to_list delete drop take merge put put_new)a,
    List: ~w(wrap flatten delete delete_at insert_at replace_at update_at duplicate)a,
    Tuple: ~w(to_list)a
  }

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
      # Direct: Enum.count(list_expr) → length(list_expr)
      {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, [arg]} = node ->
        cond do
          predicate?(arg) -> node
          match?({:ok, _}, map_keys_arg(arg)) -> map_size_call(arg)
          provably_list?(arg) -> {:length, [], [arg]}
          true -> node
        end

      # Pipeline: list_lhs |> Enum.count() → list_lhs |> length()
      {:|>, pmeta, [lhs, {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, cmeta, []}]} = node ->
        cond do
          match?({:ok, _}, map_keys_arg(lhs)) -> map_size_call(lhs)
          provably_list?(lhs) -> {:|>, pmeta, [lhs, {:length, cmeta, []}]}
          true -> node
        end

      node ->
        node
    end)
  end

  # Counting `Map.keys(m)` is `map_size(m)` exactly (=== for every input,
  # including the BadMapError raised on a non-map) and skips the intermediate
  # key-list allocation, so prefer it over `length(Map.keys(m))`.
  defp map_size_call(arg) do
    {:ok, inner} = map_keys_arg(arg)
    {:map_size, [], [inner]}
  end

  # `Map.keys(inner)` — as a direct call or as `inner |> Map.keys()`.
  defp map_keys_arg({{:., _, [{:__aliases__, _, [:Map]}, :keys]}, _, [inner]}), do: {:ok, inner}

  defp map_keys_arg({:|>, _, [lhs, {{:., _, [{:__aliases__, _, [:Map]}, :keys]}, _, []}]}),
    do: {:ok, lhs}

  defp map_keys_arg(_), do: :error

  # Direct call: Enum.count(arg)
  defp check_node({{:., meta, [mod, :count]}, _, [arg]}) do
    if enum_module?(mod) and not predicate?(arg) and provably_list?(arg) do
      {:ok, build_issue(meta)}
    else
      :error
    end
  end

  # Piped call: lhs |> Enum.count()
  defp check_node({:|>, _, [lhs, {{:., meta, [mod, :count]}, _, []}]}) do
    if enum_module?(mod) and provably_list?(lhs) do
      {:ok, build_issue(meta)}
    else
      :error
    end
  end

  defp check_node(_), do: :error

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?(_), do: false

  defp predicate?({:&, _, _}), do: true
  defp predicate?({:fn, _, _}), do: true
  defp predicate?(_), do: false

  # The argument is known to be a list when it is a list literal, a `++`
  # concatenation, a list-returning call, or a pipe whose last step returns a list.
  defp provably_list?(list) when is_list(list), do: true
  # Sourceror wraps a list literal as {:__block__, meta, [[...]]}.
  defp provably_list?({:__block__, _, [inner]}), do: provably_list?(inner)
  defp provably_list?({:++, _, [_, _]}), do: true
  defp provably_list?({:|>, _, [_lhs, step]}), do: list_returning_call?(step)

  defp provably_list?({{:., _, [{:__aliases__, _, [_mod]}, _fun]}, _, _args} = call),
    do: list_returning_call?(call)

  defp provably_list?(_), do: false

  defp list_returning_call?({{:., _, [{:__aliases__, _, [mod]}, fun]}, _, _args}) do
    case Map.fetch(@list_returning, mod) do
      {:ok, funs} -> fun in funs
      :error -> false
    end
  end

  defp list_returning_call?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :no_enum_count_for_length,
      message: """
      `Enum.count/1` on a list argument used instead of `length/1`.

      `length/1` is a BIF with no protocol dispatch overhead. Only flagged when \
      the argument is provably a list (literal, `++`, or a list-returning call) — \
      `length/1` would raise on a range/map/stream.
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
