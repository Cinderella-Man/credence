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

            case bad do
              [] ->
                node

              _ ->
                new_case = {:case, case_meta, [subject, good]}

                {:try, case_meta,
                 [
                   [
                     {{:__block__, [], [:do]}, new_case} | bad
                   ]
                 ]}
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

  defp extract_bad_opts(opts) do
    Enum.split_with(opts, fn
      {{:__block__, _, [key]}, _} when key in [:after, :rescue] -> true
      _ -> false
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
