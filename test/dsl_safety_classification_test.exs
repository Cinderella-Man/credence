defmodule Credence.Pattern.DslSafetyClassificationTest do
  @moduledoc """
  Regression guard that keeps the DSL-safety classification honest (see
  `Credence.DslGuard` and the `unsafe_in_dsl/0` callback).

  The DSL gate only protects rules that declare `unsafe_in_dsl/0`. The standing
  risk is a *future* rule whose fix flips an operator or reshapes control flow but
  forgets the flag — silently reintroducing the macro-DSL bug class (a rewrite
  that is wrong inside Ash `expr`, an Ecto query, or an Nx `defn`, yet still
  compiles).

  This test makes the flag self-enforcing. It runs each rule's real fix over that
  rule's own `*_fix_test.exs` `input` fixtures and asks the empirical question the
  classification was built on: **does the rewrite change a construct those DSLs
  reinterpret?** (`!`/`&&`/`||`/`and`/`or`/`not`/comparisons/`is_nil`/`x == nil`/
  `if`/`unless`/`cond`/`case`/`with`/`/`/`div`/`rem`/`in`.)

  A rule whose fix changes such a construct MUST either:

    * declare the families it diverges in via `unsafe_in_dsl/0`, or
    * appear in `@verified_dsl_safe` with the reason it is safe anyway — almost
      always because it only ever matches a `def`/`defp` clause head/guard or an
      existing `case`, neither of which can sit inside a DSL *expression*, or
      because the flagged `/` is function-capture arity (`&fun/1`), not division.

  A new construct-changing rule that is neither flagged nor listed fails here, with
  a message telling the author which to do.
  """
  use ExUnit.Case, async: true

  alias Credence.{RuleHelpers, RuleName}

  # Constructs that Ash.Expr / Ecto.Query / Nx.Defn reinterpret. Mirrors the
  # classification oracle the `unsafe_in_dsl` flags were derived from.
  @ops ~w(! && || and or not == != === !== < > <= >= is_nil / div rem in + - * ** <> ++ --)a
  @ctrl ~w(if unless cond case with)a

  # Rules whose fix changes a reinterpreted construct in its fixtures yet is
  # nonetheless safe inside every DSL — verified by the per-family audit. Each
  # carries NO `unsafe_in_dsl` flag on purpose; the reason must hold for any new
  # fixture too. If one of these is later changed to rewrite inside a DSL
  # expression, drop it here and add the flag.
  @verified_dsl_safe %{
    # Match only a def/defp clause head or `when` guard — never a DSL expression.
    "avoid_length_guard_less_than2" => "rewrites a def/defp `when length(v) < 2` guard head only",
    "hallucinated_guard" =>
      "rewrites hallucinated guard names (is_pos_integer, …) that aren't real functions — they never occur in compiling code (DSL or not), and the rule stands down when the name is defined/imported",
    "no_guard_equality_for_pattern_match" => "operates only on def/defp clause guards",
    "no_length_guard_to_pattern" => "rewrites a def/defp `when` length guard head only",
    "no_redundant_negated_guard" => "operates only on def/defp clause guards",
    "prefer_pattern_match_empty_string" => "matches only def/defp clauses carrying a `when` guard",
    "redundant_list_guard" => "operates only on def/defp clause guards",
    "prefer_guard_over_if" => "matches only a def/defp clause whose body is an if/else",
    "prefer_pattern_match_over_conditional_in_recursive_count" =>
      "matches only a def whose body is recursive list counting",
    "prefer_lookup_for_digit_conversion" => "matches and rewrites only module-level defp clauses",
    "no_case_on_param_dispatch" =>
      "matches only a def/defp body that is `case param`; splits to clause heads, never inside a DSL expression",
    # Match an EXISTING `case` over a subject (booleans, tuples, Map results,
    # graphemes) that no compiling Ash expr / Ecto query / Nx defn expression
    # produces. `case` itself is not universally illegal in a DSL (Nx.Defn allows
    # container matching), but a `case` on *these* subjects is not valid compiling
    # DSL code, so the rule never fires inside a real block.
    "no_case_true_false" =>
      "matches an existing `case` over true/false clauses; not valid compiling DSL code, so it never fires inside a real block",
    "no_case_tuple_guard_dispatch" =>
      "matches an existing `case` with tuple/guard clauses; not valid compiling DSL code, so it never fires inside a real block",
    "no_map_update_then_fetch" => "matches an existing `case` over Map.update/fetch in a block",
    "no_redundant_case_nil_clause" => "matches an existing `case`; keeps it, only drops a redundant nil clause",
    "prefer_function_clauses_for_list_patterns" =>
      "matches an existing `case` on list patterns; not valid compiling DSL code, so it never fires inside a real block",
    "prefer_string_slice_for_trim_last_char" => "matches an existing `case String.graphemes(...)`",
    # The flagged `/` is function-capture arity (`&fun/N`), not the division operator.
    "no_identity_enum_map" => "the `/` is capture arity in an identity-fn matcher, not division",
    "no_redundant_local_capture" => "the `/` is capture arity (`&fn/arity`), not division",
    "no_map_then_aggregate" =>
      "matches an Enum.map |> Enum.sum fusion; the `/` is capture arity and the introduced `+`/`*` — like all Enum.* here — never lands in a DSL expression",
    "unnecessary_grapheme_chunking" =>
      "matches a String.graphemes |> Enum.chunk_every(_, 1) |> Enum.map(&Enum.join) pipeline that isn't valid DSL-expression code; the `/` is capture arity and the introduced `-`/`..//` never reach a DSL expression",
    # Arithmetic/concat (+ - * <> ++) changed only inside plain-Elixir
    # Enum/reduce/recursion idioms that no DSL expression grammar can contain.
    "no_string_concat_in_loop" =>
      "rewrites an Enum.reduce(list, \"\", fn e, acc -> acc <> e end) string-build to Enum.join/map_join; the reduce+lambda+`<>` shape can't appear inside an Ash expr / Ecto query / Nx defn",
    "no_list_append_in_recursion" =>
      "matches a multi-clause def/defp with a recursive `acc ++ [x]` tail call; a function definition is never a DSL expression",
    "no_list_append_in_reduce" =>
      "matches `Enum.reduce(_, [], fn i, acc -> acc ++ [x] end)`; an Enum.reduce + lambda is not part of any DSL expression grammar",
    "prefer_enum_reverse_two" =>
      "operates on Enum.reverse/1 + list `++`; `Enum.*` and list-`++` are never DSL-expression constructs (compile errors in Ecto/Nx, never data-layer expressions in Ash)",
    "prefer_desc_sort_over_negative_take" =>
      "matches an Enum.sort |> Enum.take(-n) pipeline; `Enum.*` isn't valid in any DSL expression and the `-` is only a literal take/2 argument, never reinterpreted arithmetic",
    "no_enum_take_negative" =>
      "rewrites Enum.take(list, -n) to Enum.slice(list, -n..-1//1); `Enum.*` isn't valid in any DSL expression and the `-` is only a literal count/range bound, never reinterpreted arithmetic",
    "no_explicit_sum_reduce" =>
      "rewrites `Enum.reduce(list, 0, fn x, acc -> acc + x end)` to Enum.sum/1; the `+` lives in a reduce lambda that no DSL expression grammar can contain",
    # Plain-Elixir pipelines/reduces that cannot appear inside a DSL expression.
    "no_take_while_length_check" => "matches Enum.take_while |> length/count; not expressible in a DSL expression",
    "prefer_comprehension_for_filtered_range" =>
      "matches a literal range reduce |> reverse; not expressible in a DSL expression",
    "prefer_enum_count" => "matches a manual count idiom in plain Elixir; the rewrite isn't a DSL-expression construct",
    # Condition copied verbatim — no operator changed, no guard dropped.
    "no_unless_else" => "unless→if with branches swapped, condition unchanged (same as Kernel.unless)",
    "prefer_cond_for_nested_if" => "nested if→cond copying every condition/body verbatim; no operator change"
  }

  test "every rule whose fix changes a reinterpreted construct is classified" do
    unclassified =
      rule_deltas()
      |> Enum.filter(fn %{delta: delta} -> delta != [] end)
      |> Enum.reject(fn %{rule: rule, name: name} ->
        flagged?(rule) or Map.has_key?(@verified_dsl_safe, name)
      end)
      |> Enum.map(fn %{name: name, delta: delta} -> {name, delta} end)
      |> Enum.sort()

    assert unclassified == [], """
    These rules' fixes change a construct that Ash.Expr / Ecto.Query / Nx.Defn
    reinterpret, but they declare no `unsafe_in_dsl/0` families and are not on the
    verified-safe allowlist. Inside one of those DSLs the rewrite may be silently
    wrong (it still compiles).

    For each, do ONE of:
      • add `def unsafe_in_dsl, do: [:ash_expr | :ecto_query | :nx_defn]` (or `:all`)
        to the rule — the families where the rewrite diverges; or
      • if the rule provably cannot rewrite inside a DSL *expression* (e.g. it only
        matches a def/defp clause head/guard or an existing `case`), add it to
        @verified_dsl_safe in this test with the reason.

    #{Enum.map_join(unclassified, "\n", fn {n, d} -> "  • #{n} changes: #{Enum.join(d, ", ")}" end)}
    """
  end

  test "no stale @verified_dsl_safe entry" do
    by_name = Map.new(rule_deltas(), &{&1.name, &1})

    stale =
      for {name, _why} <- @verified_dsl_safe,
          entry = by_name[name],
          # Only flag as stale when we actually exercised fixtures and saw no change.
          entry != nil and entry.inputs > 0 and entry.delta == [],
          do: name

    assert stale == [], """
    These @verified_dsl_safe entries no longer change a reinterpreted construct in
    their fixtures — remove them so the allowlist stays meaningful: #{inspect(stale)}
    """
  end

  # --- the empirical oracle --------------------------------------------------

  defp rule_deltas do
    for file <- Path.wildcard("test/pattern/*_fix_test.exs"),
        {rule, name} = rule_for(file),
        rule != nil do
      {delta, inputs} = fixture_delta(file, rule)
      %{rule: rule, name: name, delta: delta, inputs: inputs}
    end
  end

  defp rule_for(file) do
    name = file |> Path.basename() |> String.replace_suffix("_fix_test.exs", "")

    try do
      {RuleName.derive(name, :pattern).rule_module, name}
    rescue
      _ -> {nil, name}
    end
  end

  defp flagged?(rule) do
    function_exported?(rule, :unsafe_in_dsl, 0) and rule.unsafe_in_dsl() != []
  end

  defp fixture_delta(file, rule) do
    inputs = extract_inputs(file)

    delta =
      inputs
      |> Enum.flat_map(fn input ->
        fixed =
          try do
            RuleHelpers.apply_rule_fix(rule, input)
          rescue
            _ -> input
          end

        if fixed == input, do: [], else: construct_delta(input, fixed)
      end)
      |> Enum.uniq()
      |> Enum.sort()

    {delta, length(inputs)}
  end

  # Pull every binary bound to `input` in the fix-test file (the anti-pattern
  # samples the rule's fix is exercised against).
  defp extract_inputs(file) do
    case Code.string_to_quoted(File.read!(file)) do
      {:ok, ast} ->
        {_ast, acc} =
          Macro.prewalk(ast, [], fn
            {:=, _, [{:input, _, ctx}, node]}, acc when is_atom(ctx) ->
              case string_value(node) do
                nil -> {node, acc}
                str -> {node, [str | acc]}
              end

            node, acc ->
              {node, acc}
          end)

        acc

      _ ->
        []
    end
  end

  defp string_value({:__block__, _, [s]}) when is_binary(s), do: s
  defp string_value(s) when is_binary(s), do: s
  defp string_value(_), do: nil

  # The reinterpreted constructs whose multiset changed between before and after.
  defp construct_delta(before, after_) do
    b = constructs(before)
    a = constructs(after_)

    (Map.keys(b) ++ Map.keys(a))
    |> Enum.uniq()
    |> Enum.filter(fn k -> Map.get(b, k, 0) != Map.get(a, k, 0) end)
  end

  defp constructs(src) do
    case Sourceror.parse_string(src) do
      {:ok, ast} ->
        {_ast, acc} =
          Macro.prewalk(ast, [], fn
            {op, _, [_, nil]} = n, acc when op in [:==, :!=] -> {n, [:nil_compare, op | acc]}
            {op, _, [nil, _]} = n, acc when op in [:==, :!=] -> {n, [:nil_compare, op | acc]}
            {op, _, args} = n, acc when op in @ops and is_list(args) -> {n, [op | acc]}
            {op, _, args} = n, acc when op in @ctrl and is_list(args) -> {n, [op | acc]}
            n, acc -> {n, acc}
          end)

        Enum.frequencies(acc)

      _ ->
        %{}
    end
  end
end
