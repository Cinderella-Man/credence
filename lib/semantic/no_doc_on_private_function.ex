defmodule Credence.Semantic.NoDocOnPrivateFunction do
  @moduledoc """
  Fixes compiler warnings about `@doc` on private functions.

  The Elixir compiler always discards `@doc` attributes on `defp`/`defmacrop`/
  `typep` with a warning. Under `--warnings-as-errors`, this blocks compilation.

  The fix strips the `@doc` attribute — output-identical since the compiler
  already ignores it.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, "is private, @doc attribute is always discarded")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_doc_on_private_function,
      message: "Removing @doc from private function",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    defp_line = line(diagnostic)
    lines = String.split(source, "\n")

    # Find the @doc attribute that belongs to this private function.
    # The @doc is typically 1-3 lines before the defp (with @spec in between).
    # Scan backwards from the defp line to find the nearest @doc.
    case find_doc_line(lines, defp_line) do
      nil ->
        source

      doc_start ->
        doc_end = find_doc_end(lines, doc_start)

        # Remove the @doc lines (and any trailing blank line after triple-quote @doc)
        {before, rest} = Enum.split(lines, doc_start - 1)
        after_doc = Enum.drop(rest, doc_end - doc_start + 1)

        # If the @doc used heredoc, also remove a trailing blank line if present
        after_doc =
          case after_doc do
            ["" | rest] -> rest
            other -> other
          end

        Enum.join(before ++ after_doc, "\n")
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line

  # Scan backwards from the defp line to find the nearest @doc attribute.
  # The @doc we want is the one immediately preceding this defp (possibly with
  # @spec in between). We stop if we hit another def/defp.
  defp find_doc_line(lines, defp_line) when defp_line >= 1 do
    # Scan backwards from the line before defp
    (defp_line - 1)..1//-1
    |> Enum.reduce_while(nil, fn line_no, acc ->
      line = Enum.at(lines, line_no - 1)

      cond do
        is_nil(line) ->
          {:cont, acc}

        String.match?(line, ~r/^\s*@doc\b/) ->
          {:halt, line_no}

        # Stop if we hit another def/defp - the @doc we want is above this
        String.match?(line, ~r/^\s*(def|defp|defmacro|defmacrop)\b/) ->
          {:halt, acc}

        true ->
          {:cont, acc}
      end
    end)
  end

  defp find_doc_line(_, _), do: nil

  # Find the end of a @doc attribute. If it's a heredoc, find the closing \"\"\"
  defp find_doc_end(lines, doc_start) do
    doc_line = Enum.at(lines, doc_start - 1)

    if String.contains?(doc_line, ~s(""")) do
      # Heredoc: find closing """
      find_heredoc_end(lines, doc_start + 1)
    else
      # Single-line @doc
      doc_start
    end
  end

  defp find_heredoc_end(lines, from_line) do
    Enum.reduce_while(from_line..length(lines), from_line, fn line_no, _acc ->
      line = Enum.at(lines, line_no - 1)

      if String.trim(line) == ~s(""") do
        {:halt, line_no}
      else
        {:cont, line_no}
      end
    end)
  end
end
