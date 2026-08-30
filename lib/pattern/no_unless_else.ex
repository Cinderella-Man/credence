defmodule Credence.Pattern.NoUnlessElse do
  @moduledoc """
  Detects `unless ... do ... else ... end` — a style guide violation.

  The Elixir style guide says: *"Never use `unless` with `else`.
  Rewrite these with the positive case first."*

  The fix swaps `unless` to `if` and reverses the branch bodies.
  The condition is never modified.

  ## Bad

      unless MapSet.member?(set, value) do
        :missing
      else
        :found
      end

  ## Good

      if MapSet.member?(set, value) do
        :found
      else
        :missing
      end

  ## Auto-fix

  Replaces `unless` with `if` and swaps the `do`/`else` bodies.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    eligible = eligible_unless_keys(ast)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:unless, meta, [_condition, clauses]} = node, acc ->
          if has_else?(clauses) and MapSet.member?(eligible, location(meta)) do
            {node, [build_issue(meta) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    eligible = eligible_unless_keys(ast)

    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:unless, meta, _args} = node ->
        if MapSet.member?(eligible, location(meta)), do: maybe_rewrite(node), else: node

      node ->
        node
    end)
  end

  # Parsing cannot expand an unqualified call to discover its origin. Track the
  # two lexical facts that make it unsafe to treat one as Kernel.unless: a local
  # definition in the current module, or a preceding custom import in scope.
  defp eligible_unless_keys(ast) do
    {keys, _imported?} = collect_eligible(ast, false, false)
    MapSet.new(keys)
  end

  defp collect_eligible({:__block__, _, forms}, imported?, local?) when is_list(forms) do
    Enum.reduce(forms, {[], imported?}, fn form, {keys, imported?} ->
      {form_keys, next_imported?} = collect_eligible(form, imported?, local?)
      {keys ++ form_keys, next_imported?}
    end)
  end

  defp collect_eligible({:import, _, args}, imported?, _local?) do
    {[], imported? or custom_import?(args)}
  end

  defp collect_eligible({:defmodule, _, args}, imported?, _local?) do
    body = extract_clause(List.last(args), :do)
    {keys, _inner_imported?} = collect_eligible(body, imported?, defines_unless_here?(body))
    {keys, imported?}
  end

  defp collect_eligible({:unless, meta, [_condition, clauses]} = node, imported?, local?) do
    own =
      if has_else?(clauses) and not imported? and not local?, do: [location(meta)], else: []

    {nested, _} = collect_children(node, imported?, local?)
    {own ++ nested, imported?}
  end

  defp collect_eligible(node, imported?, local?) do
    {keys, _} = collect_children(node, imported?, local?)
    {keys, imported?}
  end

  defp collect_children({_, _, children}, imported?, local?) when is_list(children) do
    collect_children(children, imported?, local?)
  end

  defp collect_children(items, imported?, local?) when is_list(items) do
    keys = Enum.flat_map(items, fn item -> elem(collect_eligible(item, imported?, local?), 0) end)
    {keys, imported?}
  end

  defp collect_children(tuple, imported?, local?) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> collect_children(imported?, local?)
  end

  defp collect_children(_node, imported?, _local?), do: {[], imported?}

  defp custom_import?([{:__aliases__, _, [:Kernel]} | _]), do: false
  defp custom_import?([:Kernel | _]), do: false
  defp custom_import?(_args), do: true

  defp defines_unless_here?(ast) do
    case ast do
      {:defmodule, _, _} ->
        false

      {dt, _, [{:unless, _, args} | _]}
      when dt in [:def, :defp, :defmacro, :defmacrop] and is_list(args) ->
        true

      {dt, _, [{:when, _, [{:unless, _, args} | _]} | _]}
      when dt in [:def, :defp, :defmacro, :defmacrop] and is_list(args) ->
        true

      {_, _, children} when is_list(children) ->
        Enum.any?(children, &defines_unless_here?/1)

      items when is_list(items) ->
        Enum.any?(items, &defines_unless_here?/1)

      tuple when is_tuple(tuple) ->
        tuple |> Tuple.to_list() |> Enum.any?(&defines_unless_here?/1)

      _ ->
        false
    end
  end

  defp location(meta), do: {Keyword.get(meta, :line), Keyword.get(meta, :column)}

  # Checks if a keyword list (from unless/if args) has an :else clause.
  defp has_else?(clauses) when is_list(clauses) do
    Enum.any?(clauses, fn
      {{:__block__, _, [:else]}, _} -> true
      _ -> false
    end)
  end

  defp has_else?(_), do: false

  # Rewrites a single unless...else node to if...else with swapped bodies.
  defp maybe_rewrite({:unless, meta, [condition, clauses]} = node) do
    if has_else?(clauses) do
      {:if, meta, [condition, swap_branches(clauses)]}
    else
      node
    end
  end

  defp maybe_rewrite(node), do: node

  # Swaps the do and else bodies in a keyword clause list.
  defp swap_branches(clauses) when is_list(clauses) do
    do_body = extract_clause(clauses, :do)
    else_body = extract_clause(clauses, :else)

    Enum.map(clauses, fn
      {{:__block__, m, [:do]}, _} -> {{:__block__, m, [:do]}, else_body}
      {{:__block__, m, [:else]}, _} -> {{:__block__, m, [:else]}, do_body}
      other -> other
    end)
  end

  # Extracts the body for a given clause key (:do or :else).
  defp extract_clause(clauses, key) do
    Enum.find_value(clauses, fn
      {{:__block__, _, [^key]}, body} -> body
      _ -> nil
    end)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_unless_else,
      message:
        "`unless` with `else` is a style violation. " <>
          "Rewrite as `if` with the branches swapped.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
