defmodule Credence.Semantic.FixUndefinedParamsInPlugRouter do
  @moduledoc """
  Fixes `undefined variable "params"` errors inside Plug.Router route blocks.

  LLMs consistently write `params["key"]` inside Plug.Router route handlers
  where `params` is not bound — the macro scope only provides `conn`. The
  compiler emits `undefined variable "params"`. The deterministic fix is
  `conn.params["key"]`, which reads from the Plug.Conn struct's params field.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "undefined variable \"params\""

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_undefined_params_in_plug_router,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    if String.contains?(msg, @match_msg) do
      Regex.replace(~r/(?<![.\w])params(?=\[)/, source, "conn.params")
    else
      source
    end
  end

  def fix(source, _diagnostic), do: source

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
