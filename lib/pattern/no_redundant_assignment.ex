defmodule Credence.Pattern.NoRedundantAssignment do
  @moduledoc """
  Detects a variable (or tuple/list of plain variables) being assigned and
  immediately returned as the last two statements of a block.

  This is a common LLM verbosity pattern where the assignment adds no value.
  In Elixir, the last expression in a block is its return value, so the
  intermediate binding is unnecessary.

  ## Tier 1 — simple variable

      # Bad
      result = compute(x)
      result

      # Good
      compute(x)

  ## Tier 2 — tuple/list of plain variables

      # Bad
      {a, b} = process(input)
      {a, b}

      # Good
      process(input)

  Patterns containing literals (e.g. `{:ok, result}`) are NOT fixed because
  the match acts as an assertion — removing it would change error behavior.
  Map patterns are never fixed because reconstruction produces a subset.

  ## Auto-fix

  Replaces the last two statements with just the RHS of the assignment.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  # ── Check ─────────────────────────────────────────────────────────

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:__block__, _meta, statements} = node, acc when is_list(statements) ->
          case check_last_pair(statements) do
            {:flag, issue} -> {node, [issue | acc]}
            :clean -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  # ── Fix ───────────────────────────────────────────────────────────

  @impl true
  def fix(source, _opts) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        if has_fixable_block?(ast) do
          ast
          |> Macro.postwalk(&maybe_rewrite_block/1)
          |> Sourceror.to_string()
        else
          source
        end

      {:error, _} ->
        source
    end
  end

  # ── Detection: last-pair check ────────────────────────────────────

  # Checks if the last two statements in a block form a redundant
  # assign-and-return pattern.
  defp check_last_pair(statements) when length(statements) >= 2 do
    second_to_last = Enum.at(statements, -2)
    last = Enum.at(statements, -1)

    case second_to_last do
      {:=, meta, [lhs, _rhs]} ->
        if fixable_pattern?(lhs) and structurally_identical?(lhs, last) do
          {:flag, build_issue(meta)}
        else
          :clean
        end

      _ ->
        :clean
    end
  end

  defp check_last_pair(_), do: :clean

  # ── Pattern classification ────────────────────────────────────────

  # A pattern is fixable if it consists entirely of plain variables.
  # Patterns with literals, pins, maps, or underscore are NOT fixable.

  # Dispatch on type explicitly to avoid clause-matching ambiguity
  # with cons cells and tuples.
  defp fixable_pattern?(pattern) when is_tuple(pattern) do
    case pattern do
      # Sourceror __block__ wrapper — unwrap and retry
      {:__block__, _, [inner]} -> fixable_pattern?(inner)
      # Plain variable
      {name, _, ctx} when is_atom(name) and is_atom(ctx) and name != :_ -> true
      # 3+ element tuple: {:{}, _, elements}
      {:{}, _, elements} when is_list(elements) -> Enum.all?(elements, &all_plain_variables?/1)
      # 2-element tuple (only matches when tuple_size is 2)
      {a, b} -> all_plain_variables?(a) and all_plain_variables?(b)
      _ -> false
    end
  end

  defp fixable_pattern?(pattern) when is_list(pattern) and pattern != [] do
    fixable_list_or_cons?(pattern)
  end

  defp fixable_pattern?(_), do: false

  # Recursively checks that every leaf in a pattern is a plain variable.
  # Handles Sourceror __block__ wrapping and the cons operator {:|, _, [h, t]}.
  defp all_plain_variables?({:__block__, _, [inner]}), do: all_plain_variables?(inner)

  defp all_plain_variables?({:|, _, [head, tail]}),
    do: all_plain_variables?(head) and all_plain_variables?(tail)

  defp all_plain_variables?({name, _, ctx})
       when is_atom(name) and is_atom(ctx) and name != :_,
       do: true

  defp all_plain_variables?(_), do: false

  # Walks a list pattern (proper or cons cell) checking all leaves are plain variables.
  defp fixable_list_or_cons?([head | tail]) do
    all_plain_variables?(head) and
      cond do
        is_list(tail) and tail != [] -> fixable_list_or_cons?(tail)
        tail == [] -> true
        true -> all_plain_variables?(tail)
      end
  end

  defp fixable_list_or_cons?(_), do: false

  # ── Structural comparison ─────────────────────────────────────────

  # Two AST nodes are structurally identical if they represent the
  # same source code, ignoring position metadata. Using Macro.to_string
  # as the normalizer handles all AST representation differences
  # (2-tuples vs {:{}, _, _}, __block__ wrapping, cons cells, etc).
  defp structurally_identical?(a, b) do
    Macro.to_string(a) == Macro.to_string(b)
  end

  # ── Check: issue construction ─────────────────────────────────────

  defp build_issue(meta) do
    %Issue{
      rule: :no_redundant_assignment,
      message:
        "Variable is assigned and immediately returned. " <>
          "The assignment is redundant — return the expression directly.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  # ── Fix: block rewriting ─────────────────────────────────────────

  defp has_fixable_block?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        _node, true ->
          {nil, true}

        {:__block__, _, statements} = node, false when is_list(statements) ->
          {node, block_is_fixable?(statements)}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp block_is_fixable?(statements) when length(statements) >= 2 do
    second_to_last = Enum.at(statements, -2)
    last = Enum.at(statements, -1)

    case second_to_last do
      {:=, _, [lhs, _rhs]} ->
        fixable_pattern?(lhs) and structurally_identical?(lhs, last)

      _ ->
        false
    end
  end

  defp block_is_fixable?(_), do: false

  # Postwalk callback: rewrites a __block__ if its last two statements
  # form a redundant assign-and-return.
  defp maybe_rewrite_block({:__block__, meta, statements} = node)
       when is_list(statements) and length(statements) >= 2 do
    second_to_last = Enum.at(statements, -2)
    last = Enum.at(statements, -1)

    case second_to_last do
      {:=, _, [lhs, rhs]} ->
        if fixable_pattern?(lhs) and structurally_identical?(lhs, last) do
          {preceding, _last_two} = Enum.split(statements, length(statements) - 2)
          {:__block__, meta, preceding ++ [rhs]}
        else
          node
        end

      _ ->
        node
    end
  end

  defp maybe_rewrite_block(node), do: node
end
