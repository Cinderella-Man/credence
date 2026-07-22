defmodule Credence.Semantic.FixAfterOrRescueInCase do
  @moduledoc """
  Fixes `case … after … end` (or `rescue`) patterns that compile-time reject
  with "unexpected option :after in \"case\"".

  LLMs confuse `case` and `try` syntax, writing `case … after … rescue … end`
  which the parser accepts but the compiler rejects. The deterministic fix
  wraps the `case` in a `try` block and moves the `after`/`rescue` clauses
  out of the `case` options and into the `try`.

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
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_after "unexpected option :after in \"case\""
  @match_rescue "unexpected option :rescue in \"case\""

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_after) or String.contains?(msg, @match_rescue)
  end

  def match?(_), do: false

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

            if Enum.any?(bad, &trigger_opt?/1) do
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

  # `catch` and `else` are also invalid in `case` but valid in `try`; they ride
  # along into the `try` so the rewrite compiles. A `case` whose only invalid
  # options are `catch`/`else` is left alone — this rule only claims the
  # `:after`/`:rescue` diagnostics.
  defp extract_bad_opts(opts) do
    Enum.split_with(opts, fn
      {{:__block__, _, [key]}, _} when key in [:after, :rescue, :catch, :else] -> true
      _ -> false
    end)
  end

  defp trigger_opt?({{:__block__, _, [key]}, _}) when key in [:after, :rescue], do: true
  defp trigger_opt?(_), do: false

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
