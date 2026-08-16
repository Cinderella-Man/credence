defmodule Credence.Semantic.NoMapHas do
  @moduledoc """
  Fixes the undefined-function error caused by `Map.has?/2`.

  `Map.has?/2` is a common typo for `Map.has_key?/2`; this rule
  deterministically renames the call to the correct function.

  ## Bad

      defmodule ExampleNMH do
        def has_key?(map, key) do
          Map.has?(map, key)
        end
      end

  ## Good

      defmodule ExampleNMH do
        def has_key?(map, key) do
          Map.has_key?(map, key)
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  # Match the target MFA only when the module is exactly the stdlib `Map`:
  # a leading boundary (start-of-string or a non-word, non-dot char) keeps
  # `SomeMap.has?/2` and `A.Map.has?/2` — where `has_key?` is *not* the known
  # intended fix — from firing this rule. See `no_map_has_check_test.exs`.
  @match_target ~r/(?:^|[^\w.])Map\.has\?\//

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    Regex.match?(@match_target, msg) and
      (String.contains?(msg, "undefined or private") or
         String.contains?(msg, "undefined function"))
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_map_has,
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
      # Rewrite only a real `Map.has?` token — the boundary capture keeps a
      # `SomeMap.has?` sharing the flagged line untouched (check/fix agree).
      {l, ^line_no} ->
        Regex.replace(~r/(^|[^\w.])Map\.has\?/, l, "\\1Map.has_key?", global: false)

      {l, _} ->
        l
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
