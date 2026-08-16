defmodule Credence.Semantic.FixNegationInGuard do
  @moduledoc """
  Fixes `!` (not-operator) in guard expressions by replacing with `not`.

  Elixir guards do not allow `!` (the Kernel not-operator macro), only the
  `not` keyword. LLMs commonly emit `!` in guards from C/JS training.
  The compiler raises:

      "invalid expression in guard, ! is not allowed in guards"

  The deterministic fix replaces `!` with `not` in `when` guard expressions.
  Semantics are identical — both produce a boolean negation — so behaviour
  is preserved.  The rewrite is scoped to `when` clauses only; `!` outside
  guards (e.g. in function bodies) is left untouched.

  ## Bad

      defmodule Example do
        def check(x) when !is_number(x), do: :error
        def negate(x), do: !x
      end

  ## Good

      defmodule Example do
        def check(x) when not is_number(x), do: :error
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
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          # The guard is always the last `when` argument; anything before it is
          # patterns (`fn a, b when guard ->` has two) and must not be rewritten.
          {:when, when_meta, [_ | _] = args}, acc ->
            {patterns, [guard]} = Enum.split(args, -1)
            {new_guard, guard_changed} = fix_negation_in_guard(guard)

            if guard_changed do
              {{:when, when_meta, patterns ++ [new_guard]}, true}
            else
              {{:when, when_meta, args}, acc}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # Recursively replace `!` with `not` in a guard expression tree.
  defp fix_negation_in_guard({:!, meta, [arg]}) do
    {new_arg, _} = fix_negation_in_guard(arg)
    {{:not, meta, [new_arg]}, true}
  end

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
