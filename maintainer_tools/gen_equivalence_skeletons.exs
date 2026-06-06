# Throwaway scaffold for the behaviour-equivalence backfill (docs/07, Phase 2).
#
#   mix run maintainer_tools/gen_equivalence_skeletons.exs
#
# For every rule in Credence.Pattern.default_rules() that does NOT already have a
# test/pattern/<base>_equivalence_test.exs, it writes a skeleton tagged
# @moduletag :equivalence_todo (excluded from the default suite), stamped with the
# rule's confirmed tier and seeded with firing snippets mechanically lifted from
# the matching <base>_check_test.exs. A human/agent fill pass then picks the
# battery dimensions, fills the expression/module, and removes the tag.
#
# Not deterministic-safe to re-run destructively: existing files are SKIPPED,
# never clobbered (protects the hand-written Phase-1 exemplars).

# ── confirmed tiers (docs/07 classification + deep-dive conversions) ──────────
# Everything not listed below is Tier 1 (expression).

t2 =
  ~w(
    no_case_on_param_dispatch no_destructure_reconstruct no_double_filter
    no_double_sort_same_list no_enum_at_midpoint_access no_guard_equality_for_pattern_match
    no_hd_tl_when_cons_bound no_is_nil_guard no_is_prefix_for_non_guard
    no_length_based_indexing no_length_guard_to_pattern no_list_append_in_recursion
    no_list_concat_with_recursive_result no_list_to_tuple_for_access
    no_manual_count_with_predicate no_manual_find no_manual_list_last
    no_manual_list_reduce no_map_get_sentinel no_map_update_then_fetch
    no_multiple_enum_at no_nested_enum_on_same_enumerable no_redundant_comparison_guard
    no_redundant_negated_guard no_repeated_div_rem no_trivial_delegation
    no_underscore_function_name no_unnecessary_catch_all_raise prefer_guard_over_if
    inconsistent_param_names non_grouped_clauses no_missing_require_logger
    no_attr_before_defmodule no_piped_regex_replace redundant_list_guard
    no_trailing_newline_in_doc prefer_heredoc_for_multi_line_doc
  )a

# Behaviour observed via Code.fetch_docs/1 (docstring), not a return value.
doc_obs = ~w(no_trailing_newline_in_doc prefer_heredoc_for_multi_line_doc)a

probe =
  ~w(
    no_anon_fn_application_in_pipe no_case_destructure_in_pipe no_eager_with_index_in_reduce
    no_explicit_max_reduce no_explicit_min_reduce no_explicit_product_reduce
    no_explicit_sum_reduce no_filter_then_count no_filter_then_first
    no_find_value_default_case no_group_by_for_frequencies no_if_empty_for_enum_min_max
    no_list_append_in_reduce no_map_keys_enum_lookup no_map_keys_or_values_for_iteration
    no_map_then_aggregate no_reduce_for_group_by no_reduce_for_map_building
    no_string_concat_in_loop no_take_while_length_check no_zip_then_map
    prefer_map_put_new use_map_join no_manual_count_with_predicate no_manual_find
    no_manual_list_reduce
  )a

# Tier 3a cosmetic — pre-filled with the deep-dive reason (no TODO, done on write).
cosmetic = %{
  no_doc_false_on_private:
    "`@doc` on a `defp` is discarded by the compiler; removing it changes no emitted code.",
  no_literal_list_typespec:
    "`@spec` is compile-only and the original does not even compile; no runtime behaviour to compare."
}

tier = fn name ->
  cond do
    Map.has_key?(cosmetic, name) -> :cosmetic
    name in t2 -> :t2
    true -> :t1
  end
end

# ── snippet extraction from <base>_check_test.exs ─────────────────────────────

negative_label? = fn label ->
  String.match?(
    label,
    ~r/\b(not|ignore|ignores|clean|skip|skips|leaves|preserve|preserves|valid|allow|allows|unchanged|safe|no-op|negative)\b/i
  ) or String.contains?(label, "n't")
end

str = fn
  bin when is_binary(bin) -> bin
  {:sigil_s, _, [{:<<>>, _, parts}, _]} -> if Enum.all?(parts, &is_binary/1), do: Enum.join(parts)
  {:sigil_S, _, [{:<<>>, _, parts}, _]} -> if Enum.all?(parts, &is_binary/1), do: Enum.join(parts)
  _ -> nil
end

snippet_strings = fn node, str ->
  {_, acc} =
    Macro.prewalk(node, [], fn
      {:=, _, [{v, _, c}, rhs]} = n, acc
      when is_atom(v) and is_atom(c) and v in [:code, :bad, :source, :input, :identity, :derived] ->
        {n, [str.(rhs) | acc]}

      {f, _, args} = n, acc when f in [:check, :flagged?, :clean?, :analyze, :fix, :issues] and is_list(args) ->
        {n, Enum.map(args, str) ++ acc}

      n, acc ->
        {n, acc}
    end)

  acc |> Enum.reject(&(is_nil(&1) or String.length(&1) < 3)) |> Enum.reverse()
end

snippets = fn base, str, snippet_strings, negative_label? ->
  path = "test/pattern/#{base}_check_test.exs"

  with true <- File.exists?(path),
       {:ok, ast} <- Code.string_to_quoted(File.read!(path)) do
    {_, tagged} =
      Macro.prewalk(ast, [], fn
        {:describe, _, [label, [do: body]]} = n, acc when is_binary(label) ->
          pol = if negative_label?.(label), do: :neg, else: :pos
          {n, Enum.map(snippet_strings.(body, str), &{pol, &1}) ++ acc}

        n, acc ->
          {n, acc}
      end)

    pos = for {:pos, s} <- tagged, do: s
    neg = for {:neg, s} <- tagged, do: s

    candidates =
      case Enum.uniq(pos -- neg) do
        [] -> snippet_strings.(ast, str) |> Enum.uniq()
        list -> list
      end

    Enum.take(candidates, 3)
  else
    _ -> []
  end
end

# ── skeleton rendering ────────────────────────────────────────────────────────

comment_block = fn snips ->
  case snips do
    [] ->
      "  #   (none auto-extracted — see the check test)"

    list ->
      list
      |> Enum.map(fn s -> "  #   " <> (s |> String.trim() |> String.replace("\n", "\n  #     ")) end)
      |> Enum.join("\n")
  end
end

render = fn full_mod, short, base, t, probe?, snips, cosmetic ->
  header = fn desc, tag? ->
    """
    defmodule Credence.Pattern.#{short}EquivalenceTest do
      @moduledoc \"\"\"
      #{desc}

      AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
      the tier, then delete the `@moduletag :equivalence_todo` line.
      \"\"\"
      use ExUnit.Case, async: true
    #{if tag?, do: "  @moduletag :equivalence_todo\n", else: ""}
      import Credence.BehaviourEquivalence
    #{if t == :t1 and not probe?, do: "  alias Credence.EquivalenceBatteries, as: B\n", else: ""}  alias #{full_mod}

      # Firing snippets lifted from #{base}_check_test.exs:
    #{comment_block.(snips)}
    """
  end

  body =
    cond do
      t == :cosmetic ->
        """
          test "#{base}: cosmetic — provably no runtime behaviour to compare" do
            assert :ok = mark_equivalence_cosmetic("#{cosmetic}")
          end
        end
        """

      probe? ->
        """
          test "#{base}: fix preserves transform call order/count over the battery" do
            assert_effect_trace_equivalent(
              "TODO: firing expression with the transform hole written as `effect.(x)`",
              rule: #{short},
              vars: [:list],
              inputs: [{[1, 2, 3], "-"}]
            )
          end
        end
        """

      t == :t2 ->
        """
          test "#{base}: fix preserves the called function's behaviour over the battery" do
            assert_equivalent_module(
              \"\"\"
              TODO: before module (lift a firing snippet from the check test)
              \"\"\",
              rule: #{short},
              call: {:todo_fun, 1},
              inputs: [[], [1, 2, 3], [:a, :b]]
            )
          end
        end
        """

      true ->
        """
          test "#{base}: fix preserves behaviour over the battery" do
            assert_equivalent(
              "TODO: firing expression (bind its free vars below)",
              rule: #{short},
              vars: [:todo],
              inputs: B.term_lists()
            )
          end
        end
        """
    end

  desc =
    cond do
      t == :cosmetic -> "Tier 3a (cosmetic) — no runtime behaviour to compare."
      t == :t2 and base in Enum.map(doc_obs, &Atom.to_string/1) ->
        "Tier 2 (module-call, doc-observation) — compare `Code.fetch_docs/1` of before/after."
      t == :t2 -> "Tier 2 (module-call) — compile before/after module, invoke a function."
      probe? -> "Tier 1 + PROBE — eval-order/double-eval over a transform hole."
      true -> "Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`."
    end

  header.(desc, t != :cosmetic) <> "\n" <> body
end

# ── drive ─────────────────────────────────────────────────────────────────────

rules = Credence.Pattern.default_rules()

{written, skipped, by_tier} =
  Enum.reduce(rules, {0, 0, %{}}, fn rule, {w, s, counts} ->
    short = rule |> Module.split() |> List.last()
    full_mod = inspect(rule)
    base = Macro.underscore(short)
    name = String.to_atom(base)
    path = "test/pattern/#{base}_equivalence_test.exs"
    t = tier.(name)
    probe? = name in probe and t != :t2
    counts = Map.update(counts, {t, probe?}, 1, &(&1 + 1))

    if File.exists?(path) do
      {w, s + 1, counts}
    else
      snips = snippets.(base, str, snippet_strings, negative_label?)
      content = render.(full_mod, short, base, t, probe?, snips, Map.get(cosmetic, name))
      File.write!(path, content)
      {w + 1, s, counts}
    end
  end)

IO.puts("\n=== equivalence skeleton scaffold ===")
IO.puts("rules: #{length(rules)}   written: #{written}   skipped (exists): #{skipped}")

by_tier
|> Enum.sort()
|> Enum.each(fn {{t, probe?}, n} ->
  IO.puts("  #{t}#{if probe?, do: " +probe", else: ""}: #{n}")
end)
