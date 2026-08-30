defmodule Credence.Semantic.FixPinAtomInExceptionCase do
  @moduledoc """
  Fixes the common LLM mistake of pinning a module atom in a `case` pattern
  inside a `rescue` block.

  When a rescue clause binds the exception to a variable `e` and then
  pattern-matches with `case e do ^exception -> …`, the pin matches a module
  atom (e.g. `ArgumentError`) against the exception struct (`%ArgumentError{…}`).
  Because atoms and structs are different types, the clause never matches at
  runtime.

  The fix replaces the bare pin `^exception` with a struct pin
  `%^exception{}`, which correctly matches the exception's `__struct__` key
  against the pinned module atom.

  The compiler emits (Elixir 1.20):

      the following clause will never match:

          ^exception ->

      because it attempts to match on the result of:

          e

      which has type:

          %{..., __exception__: term(), __struct__: atom()}

  The rule only fires when the never-matching clause is a *bare* pin — a
  guarded pin (`^exception when … ->`) or any other pattern shape is left
  alone, since the rewrite would not cover it.

  ## Bad

      defmodule CredencePinAtomLiveReproFPAIEC do
        def run(fun) do
          exception = ArgumentError

          try do
            fun.()
          rescue
            e ->
              case e do
                ^exception -> :expected
                _ -> :other
              end
          end
        end
      end

  ## Good

      defmodule CredencePinAtomLiveReproFPAIEC do
        def run(fun) do
          exception = ArgumentError

          try do
            fun.()
          rescue
            e ->
              case e do
                %^exception{} -> :expected
                _ -> :other
              end
          end
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  # The clause quoted in the warning must be exactly a bare pin (`^var ->`).
  # The captured variable name is reused by `fix/2` so that only the flagged
  # clause is rewritten, never another pin sharing the diagnostic line.
  @bare_pin_clause ~r/the following clause will never match:\n\n\s+\^([a-z_][a-zA-Z0-9_]*[?!]?) ->\n/

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, "__exception__:") and Regex.match?(@bare_pin_clause, msg)
  end

  def match?(_), do: false

  @doc """
  Only report diagnostics this rule can actually fix. The matched message can
  also fire when the flagged line no longer carries the quoted bare-pin clause
  (e.g. the clause spans lines), which would otherwise be attributed to this
  rule without being repaired.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_pin_atom_in_exception_case,
      message:
        "pinning a module atom against an exception struct never matches; " <>
          "use %^var{} to match the struct",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg} = diagnostic) do
    {target_line, target_column} = position(diagnostic)

    with [_, var] <- Regex.run(@bare_pin_clause, msg),
         {:ok, ast} <- Sourceror.parse_string(source) do
      pinned = String.to_atom(var)

      {_ast, candidates} =
        Macro.prewalk(ast, [], fn
          {:->, arrow_meta, [[{:^, pin_meta, [{^pinned, _, nil}]}], _body]} = node, acc ->
            candidate = {Keyword.get(arrow_meta, :line), Keyword.get(pin_meta, :column)}
            {node, [candidate | acc]}

          node, acc ->
            {node, acc}
        end)

      target =
        candidates
        |> Enum.filter(fn {candidate_line, _column} -> candidate_line == target_line end)
        |> Enum.min_by(
          fn {_line, column} -> column_distance(column, target_column) end,
          fn -> nil end
        )

      result =
        Macro.prewalk(ast, fn
          # A clause whose whole pattern is the bare pin of the flagged
          # variable, on the diagnostic line: rewrite `^var ->` to `%^var{}`.
          {:->, arrow_meta, [[{:^, pin_meta, [{^pinned, _, nil}]}], body]} = node ->
            location = {Keyword.get(arrow_meta, :line), Keyword.get(pin_meta, :column)}

            if location == target do
              new_pattern =
                {:%, pin_meta, [{:^, pin_meta, [{pinned, pin_meta, nil}]}, {:%{}, pin_meta, []}]}

              {:->, arrow_meta, [[new_pattern], body]}
            else
              node
            end

          other ->
            other
        end)

      if result == ast do
        source
      else
        Sourceror.to_string(result)
      end
    else
      _ -> source
    end
  end

  defp position(%{position: {line, column}}), do: {line, column}
  defp position(%{position: line}) when is_integer(line), do: {line, nil}
  defp line(diagnostic), do: diagnostic |> position() |> elem(0)

  defp column_distance(_column, nil), do: 0
  defp column_distance(nil, _target_column), do: 0
  defp column_distance(column, target_column), do: abs(column - target_column)
end
