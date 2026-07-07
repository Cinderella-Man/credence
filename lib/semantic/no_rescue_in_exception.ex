defmodule Credence.Semantic.NoRescueInException do
  @moduledoc """
  Fixes the common LLM mistake of using `rescue e in Exception` which causes a
  compilation warning (treated as error) because `Exception` is not a struct.

  The compiler emits:

      struct Exception is undefined (there is such module but it does not define a struct)

  The correct syntax is a simple rescue without a type:

      rescue e in Exception -> ...   # WRONG — warns
      rescue e -> ...                 # correct
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "struct Exception is undefined"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_rescue_in_exception,
      message: "rescue e in Exception is not valid; use a plain rescue clause",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      result =
        Macro.prewalk(ast, fn
          {:in, _meta, [{_name, _, nil} = var, {:__aliases__, _, [:Exception]}]} -> var
          other -> other
        end)

      Sourceror.to_string(result)
    else
      _ -> source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
