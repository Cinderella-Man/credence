defmodule Credence.Semantic.NoDocOnPrivateFunction do
  @moduledoc """
  Fixes compiler warnings about `@doc` on private functions.

  The Elixir compiler always discards `@doc` attributes on `defp`/`defmacrop`/
  `typep` with a warning. Under `--warnings-as-errors`, this blocks compilation.

  The fix strips the `@doc` attribute — output-identical since the compiler
  already ignores it.

  ## Comments

  A comment on its own line above the `@doc` is **kept** — it survives the
  deletion and ends up above the `defp`, which is where a reader would expect a
  note about the function.

  A comment TRAILING the `@doc` line itself is removed with it, and that is
  deliberate rather than an oversight: it annotates the documentation being
  deleted as stale, so carrying it down onto the `defp` would re-attach it to
  something it was not written about. Both shapes are pinned in the fix tests.

  ## Bad

      defmodule NdpDrop do
        @doc "helper docs"  # TODO: revisit
        defp helper(x), do: x
        def pub(x), do: helper(x)
      end

  ## Good

      defmodule NdpDrop do
        defp helper(x), do: x
        def pub(x), do: helper(x)
      end

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
    pos_line = line(diagnostic)
    lines = String.split(source, "\n")

    # Find the @doc attribute that belongs to this private function.
    # The diagnostic position may point to the @doc line itself or the defp
    # line — handle both by first checking the current line, then scanning
    # backwards.  Skip @doc false (intentionally undocumented).
    case find_doc_line(lines, pos_line) do
      nil ->
        source

      doc_start ->
        # Don't strip @doc false — it's intentional, not stale documentation.
        doc_line_text = Enum.at(lines, doc_start - 1)

        if doc_line_text && String.match?(doc_line_text, ~r/^\s*@doc\s+false\s*$/) do
          source
        else
          doc_end = find_doc_end(lines, doc_start)

          # Remove the @doc lines (and any trailing blank line after triple-quote @doc)
          {before, rest} = Enum.split(lines, doc_start - 1)
          {removed, after_doc} = Enum.split(rest, doc_end - doc_start + 1)

          # If the @doc used heredoc, also remove a trailing blank line if present
          after_doc =
            case after_doc do
              ["" | rest] -> rest
              other -> other
            end

          # Safety net: only strip when the lines we're removing form a complete,
          # self-contained `@doc` expression. The line-based surgery handles
          # heredoc and single-line `@doc`, but a multi-line non-heredoc doc
          # (e.g. `@doc "a" <>\n  "b"`) would cut only the first line and strand
          # the continuation — `@doc "a" <>` doesn't parse on its own, so we
          # detect that and leave the source untouched (the warning stays, but
          # valid code is never broken nor traded for a new "unused literal").
          if parses?(Enum.join(removed, "\n")) do
            Enum.join(before ++ after_doc, "\n")
          else
            source
          end
        end
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line

  defp parses?(source), do: match?({:ok, _}, Code.string_to_quoted(source))

  # Find the @doc attribute belonging to the private function at `target_line`.
  #
  # The diagnostic position may be:
  #   • the @doc line itself  (compiler points at the attribute), or
  #   • the defp line          (compiler points at the definition).
  #
  # Strategy: check the target line first; if it is @doc, return it.
  # Otherwise scan backwards looking for @doc, stopping if we hit another
  # def/defp boundary.
  defp find_doc_line(lines, target_line) when target_line >= 1 do
    current = Enum.at(lines, target_line - 1)

    cond do
      # The target line IS the @doc — use it directly.
      current && String.match?(current, ~r/^\s*@doc\b/) ->
        target_line

      # The target line is a def/defp — scan backwards for its @doc.
      current && String.match?(current, ~r/^\s*(def|defp|defmacro|defmacrop)\b/) ->
        scan_backwards_for_doc(lines, target_line - 1)

      # Target line is something else (e.g. @spec) — scan backwards.
      true ->
        scan_backwards_for_doc(lines, target_line - 1)
    end
  end

  defp find_doc_line(_, _), do: nil

  defp scan_backwards_for_doc(lines, from_line) when from_line >= 1 do
    from_line..1//-1
    |> Enum.reduce_while(nil, fn line_no, acc ->
      line = Enum.at(lines, line_no - 1)

      cond do
        is_nil(line) ->
          {:cont, acc}

        String.match?(line, ~r/^\s*@doc\b/) ->
          {:halt, line_no}

        # Stop if we hit another def/defp — the @doc we want is above this.
        String.match?(line, ~r/^\s*(def|defp|defmacro|defmacrop)\b/) ->
          {:halt, acc}

        true ->
          {:cont, acc}
      end
    end)
  end

  defp scan_backwards_for_doc(_, _), do: nil

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
