defmodule Credence.Semantic.FixNegationInGuard do
  @moduledoc """
  Fixes `!` (not-operator) in guard expressions with an equivalent guard.

  Elixir guards do not allow `!` (the Kernel not-operator macro), only the
  `not` keyword. LLMs commonly emit `!` in guards from C/JS training.
  The compiler raises:

      "invalid expression in guard, ! is not allowed in guards"

  The deterministic fix replaces `!value` with `value in [false, nil]` in
  `when` guard expressions. This preserves `!`'s truthiness semantics, unlike
  strict boolean `not`. The rewrite is scoped to `when` clauses only; `!` outside
  guards (e.g. in function bodies) is left untouched.

  ## Bad

      defmodule ExampleFNIG do
        def check(x) when !is_number(x), do: :error
        def negate(x), do: !x
      end

  ## Good

      defmodule ExampleFNIG do
        def check(x) when is_number(x) in [false, nil], do: :error
        def negate(x), do: !x
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "! is not allowed in guards"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_negation_in_guard,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} = fix_guards(ast)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # Quoted expressions are data, not executable guards in this source file.
  defp fix_guards({:quote, _meta, _args} = node), do: {node, false}

  defp fix_guards({:when, when_meta, [_ | _] = args}) do
    # The guard is always the last `when` argument; anything before it is
    # patterns (`fn a, b when guard ->` has two). We recurse there only to find
    # chained `when` nodes, never to rewrite a bare `!` in a pattern.
    {patterns, [guard]} = Enum.split(args, -1)

    {new_patterns, patterns_changed} =
      Enum.map_reduce(patterns, false, fn pattern, acc ->
        {new_pattern, changed} = fix_guards(pattern)
        {new_pattern, acc || changed}
      end)

    {new_guard, guard_changed} = fix_negation_in_guard(guard)

    {{:when, when_meta, new_patterns ++ [new_guard]}, patterns_changed || guard_changed}
  end

  defp fix_guards({form, meta, args}) when is_list(args) do
    {new_args, changed} =
      Enum.map_reduce(args, false, fn arg, acc ->
        {new_arg, arg_changed} = fix_guards(arg)
        {new_arg, acc || arg_changed}
      end)

    {{form, meta, new_args}, changed}
  end

  defp fix_guards(nodes) when is_list(nodes) do
    Enum.map_reduce(nodes, false, fn node, acc ->
      {new_node, changed} = fix_guards(node)
      {new_node, acc || changed}
    end)
  end

  defp fix_guards(node) when is_tuple(node) do
    {elements, changed} = node |> Tuple.to_list() |> fix_guards()
    {List.to_tuple(elements), changed}
  end

  defp fix_guards(node), do: {node, false}

  # Recursively replace `!value` with the guard-safe truthiness equivalent.
  defp fix_negation_in_guard({:!, meta, [arg]}) do
    {new_arg, _} = fix_negation_in_guard(arg)
    {{:in, meta, [new_arg, [false, nil]]}, true}
  end

  defp fix_negation_in_guard({:quote, _meta, _args} = node), do: {node, false}

  defp fix_negation_in_guard({op, meta, args}) when is_list(args) do
    {new_args, changed} =
      Enum.map_reduce(args, false, fn arg, acc ->
        {new_arg, arg_changed} = fix_negation_in_guard(arg)
        {new_arg, acc || arg_changed}
      end)

    {{op, meta, new_args}, changed}
  end

  defp fix_negation_in_guard(node), do: {node, false}

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
