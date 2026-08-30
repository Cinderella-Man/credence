defmodule Credence.Semantic.FixAfterOrRescueInCase do
  @moduledoc """
  Fixes `case … after … end` (or `rescue`, or `catch`) patterns that
  compile-time reject with "unexpected option :after in \"case\"".

  LLMs confuse `case` and `try` syntax, writing `case … after … rescue … end`
  which the parser accepts but the compiler rejects. The deterministic fix
  wraps the `case` in a `try` block and moves the `after`/`rescue`/`catch`
  clauses out of the `case` options and into the `try`.

  ## Bad (compiles with error)

      case :ok do
        :ok -> :success
        _ -> :failure
      after
        IO.puts("done")
      end

  ## Good

      try do
        case :ok do
          :ok -> :success
          _ -> :failure
        end
      after
        IO.puts("done")
      end

  ## Why `else` is refused rather than moved

  `after`, `rescue` and `catch` mean the same thing in `try` as the author
  evidently intended in `case`, so moving them keeps the answer. `else` does
  not: a `try`'s `else` clauses match the **success value of the body**, not
  the fallthrough of the `case`. Moving it therefore changes what the program
  returns, and both shapes were verified by execution:

      # a catch-all `else` intercepts the case's own result
      try do
        case :ok do
          :ok -> :success
        end
      else
        _ -> :err
      end
      #=> :err, where the author's evident intent is :success

      # a non-exhaustive `else` raises where the original merely failed to compile
      #=> ** (TryClauseError)

  So a `case` carrying an `else` is left alone entirely — including when it
  also carries an `after`/`rescue`/`catch` this rule could otherwise move.
  Declining costs a compile error the author can retry; rewriting costs a
  program that compiles clean and returns a different answer.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_after "unexpected option :after in \"case\""
  @match_rescue "unexpected option :rescue in \"case\""
  @match_catch "unexpected option :catch in \"case\""

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_after) or String.contains?(msg, @match_rescue) or
      String.contains?(msg, @match_catch)
  end

  def match?(_), do: false

  @doc false
  # The decline guard IS the fix, per the house idiom: a guard that
  # approximates it would be a second implementation of the same decision and
  # would drift from it. A `case` carrying an `else` has no faithful rewrite,
  # so this rule yields the slot rather than consuming the diagnostic.
  def should_report?(diagnostic, source), do: fix(source, diagnostic) != source

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_after_or_rescue_in_case,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      result =
        Macro.prewalk(ast, fn
          {:case, case_meta, [subject, opts]} = node when is_list(opts) ->
            {bad, good} = extract_bad_opts(opts)

            if Enum.any?(bad, &trigger_opt?/1) and not Enum.any?(bad, &else_opt?/1) do
              new_case = {:case, case_meta, [subject, good]}

              {:try, case_meta,
               [
                 [
                   {{:__block__, [], [:do]}, new_case} | bad
                 ]
               ]}
            else
              node
            end

          node ->
            node
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

  # `after`, `rescue`, `catch` and `else` are all invalid in `case` and valid in
  # `try`. The first three keep their meaning across the move, so they both
  # trigger the rewrite and ride along in it. `else` does not keep its meaning
  # (see the moduledoc), so its presence vetoes the whole rewrite.
  defp extract_bad_opts(opts) do
    Enum.split_with(opts, fn
      {{:__block__, _, [key]}, _} when key in [:after, :rescue, :catch, :else] -> true
      _ -> false
    end)
  end

  defp trigger_opt?({{:__block__, _, [key]}, _}) when key in [:after, :rescue, :catch], do: true
  defp trigger_opt?(_), do: false

  defp else_opt?({{:__block__, _, [:else]}, _}), do: true
  defp else_opt?(_), do: false

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
