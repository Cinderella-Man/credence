defmodule Credence.Semantic.NoUnreachableCaseClauseByType do
  @moduledoc """
  Removes a `case` clause the compiler proved can never match.

  LLMs hallucinate atoms in `case` expressions matching function return values
  (e.g. `:dt` for `DateTime.compare/2`, whose return type is `:eq | :gt | :lt`).
  The compiler emits (Elixir 1.20):

      the following clause will never match:

          :dt ->

      because it attempts to match on the result of:

          DateTime.compare(a, b)

      which has type:

          dynamic(:eq or :gt or :lt)

  The fix deletes the dead clause. That is behaviour-preserving by construction:
  the compiler has proved the clause body is unreachable, so no input can reach
  it before or after. Everything else is left alone.

  ## What the rule deliberately skips

  The rewrite only fires on the narrow shape it can delete safely:

    * the quoted clause must be a **bare atom pattern** (`:dt ->`). A guarded
      clause (`:dt when x > 0 ->`), a tuple/binary/string pattern, or a pin is
      left alone — the deletion is only provably safe for the exact clause the
      compiler quoted, and those shapes are not matched here.
    * the dead clause must be found **on the diagnostic's line**, so a live
      `:dt ->` clause in an unrelated `case` elsewhere in the file is never
      deleted.
    * exactly **one** clause in the file may match that line-and-atom pair. If
      two `case` expressions share a line (`f(case a do … end, case b do … end)`)
      only one of them is dead, so the rule declines rather than guess.
    * a `case` may not be emptied. Deleting the last remaining clause would
      produce `case x do end`, which does not compile.

  `should_report?/2` re-runs `fix/2`, so a diagnostic the rewrite declines is
  not reported as an issue either — the check and the fix always agree.

  ## Ordering — this rule runs after the specific ones

  `the following clause will never match` is also claimed by rules that own one
  particular hallucinated clause and *repair* it instead of deleting it —
  `FixMapFetchNoneClause` rewrites a `:none` clause over `Map.fetch/2` to
  `:error`, preserving the failure branch this rule would simply remove.
  Semantic dispatch is `Enum.find`: first match wins, no fall-through.

  At the default 500 the winner came from the alphabetical tiebreak in
  `Enum.sort_by(&{&1.priority(), &1})` — `FixMapFetchNoneClause` won only
  because `F` sorts before `N`. Declaring **501** says the real thing once: the
  general deletion yields to a specific repair. docs/20 §4; enforced by
  `test/dispatch_contention_test.exs`.

  ## Bad

      defmodule CredenceUnreachableCaseLiveReproNUCCBT do
        def sort_order(a, b) do
          case DateTime.compare(a, b) do
            :lt -> :asc
            :gt -> :desc
            :eq -> :same
            :dt -> :unknown
          end
        end
      end

  ## Good

      defmodule CredenceUnreachableCaseLiveReproNUCCBT do
        def sort_order(a, b) do
          case DateTime.compare(a, b) do
            :lt -> :asc
            :gt -> :desc
            :eq -> :same
          end
        end
      end
  """
  use Credence.Semantic.Rule

  # The general deletion yields to rules that repair a specific clause — see
  # "## Ordering" above.
  @impl true
  def priority, do: 501
  alias Credence.Issue

  # The clause quoted in the warning must be exactly a bare atom pattern
  # (`:dt ->`). The captured atom is reused by `fix/2` so that only that
  # pattern is deleted, never another clause on the flagged line.
  @dead_atom_clause ~r/the following clause will never match:\n\n\s+:([a-zA-Z_][a-zA-Z0-9_@]*[?!]?) ->\n/

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, "because it attempts to match on the result of:") and
      Regex.match?(@dead_atom_clause, msg)
  end

  def match?(_), do: false

  @doc """
  Only report diagnostics this rule can actually fix. The matched message also
  fires for clauses the deletion deliberately skips (a `fn`/`with` clause rather
  than a `case` one, a clause that is the only one left, a line shared by two
  `case` expressions), which would otherwise be attributed to this rule without
  being repaired.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_unreachable_case_clause_by_type,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg} = diagnostic) when is_binary(msg) do
    with [_, atom_name] <- Regex.run(@dead_atom_clause, msg),
         target_line when is_integer(target_line) <- line(diagnostic),
         {:ok, ast} <- Sourceror.parse_string(source),
         {:ok, new_ast} <- delete_clause(ast, String.to_atom(atom_name), target_line) do
      Sourceror.to_string(new_ast)
    else
      _ -> source
    end
  end

  def fix(source, _diagnostic), do: source

  # Delete the dead clause from the `case` that owns the flagged line. Returns
  # `:error` unless exactly one clause was deleted, so an ambiguous line (two
  # `case`s sharing it) leaves the source untouched.
  defp delete_clause(ast, target_atom, target_line) do
    {new_ast, deleted} =
      Macro.prewalk(ast, 0, fn
        {:case, case_meta, [subject, [{{:__block__, do_meta, [:do]}, clauses}]]} = node, acc
        when is_list(clauses) ->
          {dead, kept} = Enum.split_with(clauses, &dead_clause?(&1, target_atom, target_line))

          # Never empty a `case` — `case x do end` does not compile.
          if dead != [] and kept != [] do
            {{:case, case_meta, [subject, [{{:__block__, do_meta, [:do]}, kept}]]},
             acc + length(dead)}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    if deleted == 1, do: {:ok, new_ast}, else: :error
  end

  # A clause whose whole pattern is the flagged bare atom, on the flagged line.
  defp dead_clause?({:->, _meta, [[{:__block__, pattern_meta, [atom]}], _body]}, target, line)
       when is_atom(atom) do
    atom == target and Keyword.get(pattern_meta, :line) == line
  end

  defp dead_clause?(_clause, _target, _line), do: false

  defp line(%{position: {line, _col}}) when is_integer(line), do: line
  defp line(%{position: line}) when is_integer(line), do: line
  defp line(_diagnostic), do: nil
end
