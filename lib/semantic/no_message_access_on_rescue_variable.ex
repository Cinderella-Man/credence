defmodule Credence.Semantic.NoMessageAccessOnRescueVariable do
  @moduledoc """
  Fixes the compiler warning caused by accessing `.message` on a bare-rescue
  variable.

  LLMs frequently write `rescue e -> e.message` but Elixir's type system warns
  that a bare-rescue variable has unknown struct fields; the `.message` access
  triggers "unknown key .message" which fails `--warnings-as-errors`.

  The deterministic fix is `Exception.message(e)`:

      rescue e -> {:error, e.message}                 # WRONG — warns
      rescue e -> {:error, Exception.message(e)}      # correct
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "unknown key .message"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_message_access_on_rescue_variable,
      message:
        "accessing .message on a bare-rescue variable is unsafe; use Exception.message/1",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      result =
        Macro.prewalk(ast, fn
          {{:., meta_dot, [var, :message]}, meta_call, []} ->
            {{:., meta_dot,
              [{:__aliases__, [line: meta_dot[:line] || 0], [:Exception]}, :message]},
             meta_call, [var]}

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

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
