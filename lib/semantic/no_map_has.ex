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
  alias Credence.SourceMask

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
    column = column(diagnostic)

    source
    |> SourceMask.lines()
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn
      {{line, shadow}, ^line_no} ->
        replace_diagnosed_call(line, shadow, column)

      {{line, _shadow}, _} ->
        line
    end)
  end

  defp replace_diagnosed_call(line, shadow, column) when is_integer(column) do
    with {:ok, offset} <- SourceMask.byte_offset(shadow, 1, column),
         "has?" <- binary_part(shadow, offset, min(4, byte_size(shadow) - offset)) do
      <<before::binary-size(^offset), "has?", after_call::binary>> = line
      before <> "has_key?" <> after_call
    else
      _ -> replace_literal_map_call(line, shadow)
    end
  end

  defp replace_diagnosed_call(line, shadow, _column), do: replace_literal_map_call(line, shadow)

  # Line-only diagnostics predate compiler columns. Keep their established,
  # conservative behavior while ensuring the match is in code, not prose.
  defp replace_literal_map_call(line, shadow) do
    SourceMask.replace_code(
      line,
      shadow,
      ~r/(?:^|[^\w.])\KMap\.has\?/,
      "Map.has_key?",
      global: false
    )
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line

  defp column(%{position: {_line, column}}) when is_integer(column), do: column
  defp column(_diagnostic), do: nil
end
