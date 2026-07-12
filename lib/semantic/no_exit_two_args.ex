defmodule Credence.Semantic.NoExitTwoArgs do
  @moduledoc """
  Fixes calls to `exit/2` by qualifying them as `Process.exit/2`.

  LLMs frequently write `exit(pid, reason)` (from the Python `os._exit` /
  `sys.exit` idiom), which produces:

      undefined function exit/2 (expected Module to define such a function
      or for it to be imported, but none are available)

  `Kernel.exit/1` exists but `exit/2` does not; the correct Elixir call is
  `Process.exit/2`. The fix replaces the bare `exit(` call with `Process.exit(`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "undefined function exit/2"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_exit_two_args,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    line_no = line(diagnostic)

    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn
      {ln, ^line_no} ->
        ln
        |> String.replace("exit(", "Process.exit(", global: false)
      {ln, _} ->
        ln
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
