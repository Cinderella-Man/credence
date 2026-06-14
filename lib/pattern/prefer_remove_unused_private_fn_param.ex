defmodule Credence.Pattern.PreferRemoveUnusedPrivateFnParam do
  @moduledoc """
  Detects private functions (`defp`) with parameters that are never read in
  any clause, and removes them together with the matching arguments at every
  call site.

  ## Why this matters

  An unused parameter is dead code — often a leftover from an unfinished
  refactor. Removing it makes the function's actual contract visible and stops
  callers from constructing a value that nobody reads.

  Only **private** functions are flagged. Public API surfaces may carry
  parameters for future extensibility or protocol conformance; this rule does
  not judge those.

  ### Exemptions (intentional / load-bearing parameters)

  Two kinds of "unused" parameter are deliberately left alone, because removing
  them would fight the author or change behaviour:

    * **`_`-prefixed parameters** (`_table`, `_opts`) — the underscore is the
      author's explicit "I know this is unused; it is kept for the signature,
      arity, callback contract, or future use."
    * **parameters reused in another argument's pattern** — a non-linear match
      like `f(pk, [pk | tail])` only matches when the positions agree, so the
      name is load-bearing even though it never appears in the body.

  ## Bad

      # `cache` is never used and not underscored
      defp compute(x, cache), do: x + 1

      # callers pass a pointless value:
      compute(value, nil)

  ## Good

      defp compute(x), do: x + 1

      compute(value)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    groups = collect_private_fn_groups(ast)

    Enum.flat_map(groups, fn {name, arity, clauses} ->
      case find_unused_param_indices(clauses) do
        [] ->
          []

        unused ->
          {_, meta, _} = hd(clauses)

          [
            %Issue{
              rule: :prefer_remove_unused_private_fn_param,
              message:
                "Private function `#{name}/#{arity}` has unused parameter(s) " <>
                  "(#{format_positions(unused)}). Remove them and update all call sites.",
              meta: %{line: Keyword.get(meta, :line)}
            }
          ]
      end
    end)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.get(opts, :source, "")
    groups = collect_private_fn_groups(ast)

    Credence.RuleHelpers.patches_from_ast_transform(ast, source, fn tree ->
      Enum.reduce(groups, tree, fn {name, _arity, clauses}, acc ->
        case find_unused_param_indices(clauses) do
          [] ->
            acc

          unused ->
            acc
            |> remove_params_from_defp(name, unused)
            |> remove_args_from_calls(name, unused)
        end
      end)
    end)
  end

  # ── Collecting private function groups ────────────────────────────────

  defp collect_private_fn_groups(ast) do
    {_ast, clauses} =
      Macro.prewalk(ast, [], fn
        {:defp, _, _} = node, acc -> {node, [node | acc]}
        node, acc -> {node, acc}
      end)

    clauses
    |> Enum.reverse()
    |> Enum.group_by(fn clause ->
      {name, args} = extract_defp_name_and_args(clause)
      {name, length(args)}
    end)
    |> Enum.map(fn {{name, arity}, group} -> {name, arity, group} end)
  end

  defp extract_defp_name_and_args({:defp, _, [{:when, _, [{name, _, args}, _guard]}, _body]})
       when is_atom(name) and is_list(args),
       do: {name, args}

  defp extract_defp_name_and_args({:defp, _, [{name, _, args}, _body]})
       when is_atom(name) and is_list(args),
       do: {name, args}

  defp extract_defp_name_and_args(_), do: {:unknown, []}

  # ── Finding unused parameters ─────────────────────────────────────────

  defp find_unused_param_indices(clauses) do
    args_per_clause = Enum.map(clauses, &extract_defp_args/1)

    case args_per_clause do
      # A zero-arity head (`defp foo do ... end`) has no params to remove, and
      # `0..(arity - 1)` would become the non-empty `0..-1` range. Bail out
      # unless the first clause actually has positional arguments.
      [first | _] when first != [] ->
        arity = length(first)

        Enum.reduce(0..(arity - 1), [], fn pos, acc ->
          if param_unused_at_position?(pos, args_per_clause, clauses) do
            acc ++ [pos]
          else
            acc
          end
        end)

      _ ->
        []
    end
  end

  # A parameter at `pos` is unused if:
  #  1. Every clause has a variable (not a literal/pattern) at that position
  #  2. All those variables share the same base name
  #  3. That name is not referenced in any clause's body or guard
  defp param_unused_at_position?(pos, args_per_clause, clauses) do
    params_at_pos = Enum.map(args_per_clause, fn args -> Enum.at(args, pos) end)

    base_names = Enum.map(params_at_pos, &extract_base_name/1)

    # All must be variables with the same base name
    case base_names do
      [first | rest] ->
        # An `_`-prefixed name in any clause means the author deliberately
        # marked the parameter unused (kept for the signature/arity/contract).
        # Respect that — only remove a param the author left un-underscored.
        # A name reused in another argument's pattern is load-bearing — a
        # non-linear match like `f(pk, [pk | tail])` only matches when the
        # positions agree; removing it changes what the clause matches.
        first != nil and first != "_" and
          Enum.all?(rest, fn n -> n == first end) and
          not any_underscored?(params_at_pos) and
          not used_in_other_arg_patterns?(first, pos, args_per_clause) and
          base_unused_in_all_clauses?(first, clauses)

      _ ->
        false
    end
  end

  # True if the parameter at this position is `_`-prefixed in any clause.
  defp any_underscored?(params_at_pos) do
    Enum.any?(params_at_pos, fn
      {name, _, ctx} when is_atom(name) and is_atom(ctx) ->
        String.starts_with?(Atom.to_string(name), "_")

      _ ->
        false
    end)
  end

  # True if `base_name` appears in some *other* argument's pattern in any clause.
  defp used_in_other_arg_patterns?(base_name, pos, args_per_clause) do
    Enum.any?(args_per_clause, fn args ->
      args
      |> Enum.with_index()
      |> Enum.any?(fn {arg, idx} -> idx != pos and name_in_pattern?(arg, base_name) end)
    end)
  end

  defp name_in_pattern?(pattern, base_name) do
    {_, found} =
      Macro.prewalk(pattern, false, fn node, acc ->
        {node, acc or extract_base_name(node) == base_name}
      end)

    found
  end

  defp base_unused_in_all_clauses?(base_name, clauses) do
    base_atom = String.to_atom(base_name)
    underscore_atom = String.to_atom("_" <> base_name)

    Enum.all?(clauses, fn clause ->
      guard = extract_defp_guard(clause)
      body = extract_defp_body(clause)

      not name_used_in?(base_atom, guard) and not name_used_in?(base_atom, body) and
        not name_used_in?(underscore_atom, guard) and not name_used_in?(underscore_atom, body)
    end)
  end

  defp extract_defp_args({:defp, _, [{:when, _, [{_, _, args}, _]}, _]}) when is_list(args),
    do: args

  defp extract_defp_args({:defp, _, [{_, _, args}, _]}) when is_list(args), do: args
  defp extract_defp_args(_), do: []

  defp extract_base_name({:_, _, _}), do: "_"

  defp extract_base_name({name, _, ctx}) when is_atom(name) and is_atom(ctx) do
    str = Atom.to_string(name)
    if String.starts_with?(str, "_"), do: String.trim_leading(str, "_"), else: str
  end

  defp extract_base_name(_), do: nil

  defp extract_defp_guard({:defp, _, [{:when, _, [_, guard]}, _]}), do: guard
  defp extract_defp_guard(_), do: nil

  defp extract_defp_body({:defp, _, [{:when, _, _}, body]}), do: body
  defp extract_defp_body({:defp, _, [_, body]}), do: body
  defp extract_defp_body(_), do: nil

  defp name_used_in?(_name, nil), do: false

  defp name_used_in?(name, ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn node, acc ->
        case node do
          {^name, _, ctx} when is_atom(ctx) -> {node, true}
          _ -> {node, acc}
        end
      end)

    found
  end

  # ── Removing parameters from defp clauses ─────────────────────────────

  defp remove_params_from_defp(tree, fn_name, unused) do
    Macro.postwalk(tree, fn node -> rewrite_defp_clause(node, fn_name, unused) end)
  end

  defp rewrite_defp_clause(
         {:defp, defp_meta, [{:when, when_meta, [{name, name_meta, args}, guard]}, body]},
         fn_name,
         unused
       )
       when name == fn_name and is_list(args) do
    new_args = remove_at_indices(args, unused)
    {:defp, defp_meta, [{:when, when_meta, [{name, name_meta, new_args}, guard]}, body]}
  end

  defp rewrite_defp_clause(
         {:defp, defp_meta, [{name, name_meta, args}, body]},
         fn_name,
         unused
       )
       when name == fn_name and is_list(args) do
    new_args = remove_at_indices(args, unused)
    {:defp, defp_meta, [{name, name_meta, new_args}, body]}
  end

  defp rewrite_defp_clause(node, _fn_name, _unused), do: node

  # ── Removing arguments from call sites ────────────────────────────────

  defp remove_args_from_calls(tree, fn_name, unused) do
    Macro.postwalk(tree, fn node -> rewrite_call_site(node, fn_name, unused) end)
  end

  defp rewrite_call_site({name, meta, args}, fn_name, unused)
       when name == fn_name and is_list(args) and args != [] do
    new_args = remove_at_indices(args, unused)
    {name, meta, new_args}
  end

  defp rewrite_call_site(node, _fn_name, _unused), do: node

  # ── Helpers ───────────────────────────────────────────────────────────

  defp remove_at_indices(list, indices) do
    index_set = MapSet.new(indices)

    Enum.reject(Enum.with_index(list), fn {_, idx} -> MapSet.member?(index_set, idx) end)
    |> Enum.map(fn {elem, _} -> elem end)
  end

  defp format_positions(indices) do
    indices
    |> Enum.map_join(", ", &(to_string(&1 + 1) <> suffix(&1)))
  end

  defp suffix(0), do: "st"
  defp suffix(1), do: "nd"
  defp suffix(2), do: "rd"
  defp suffix(_), do: "th"
end
