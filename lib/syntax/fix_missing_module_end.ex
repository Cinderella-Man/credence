defmodule Credence.Syntax.FixMissingModuleEnd do
  @moduledoc """
  Repairs source whose trailing `do` blocks were never closed — most commonly a
  `defmodule` (or `def`) missing its final `end`.

  LLMs repeatedly emit a complete module body but drop the closing `end`(s), so
  the parser reaches EOF with an open `do` block and reports
  `missing terminator: end`. It is purely structural, so this is a REPAIR:
  append the missing `end` at end-of-file.

  Detection is driven by the parser — `Code.string_to_quoted/1` reports
  `missing terminator: end` with `expected_delimiter: :end` only when an opened
  block ran off the end of the file. The fix appends one `end`, re-parses, and
  repeats, so several missing `end`s are closed in order; it stops the moment
  the source parses or the error changes (e.g. an unclosed `(` expecting `)`, or
  a mismatched delimiter — both left for other rules). It never fires when the
  first parse error is something other than a missing `end`.

  ## Bad (won't parse — missing terminator: end)

      defmodule Solution do
        def f(x), do: x

  ## Good

      defmodule Solution do
        def f(x), do: x
      end
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @impl true
  def analyze(source) do
    case detect(source) do
      {:ok, line} ->
        [
          %Issue{
            rule: :missing_module_end,
            message: "Unclosed `do` block — the file ends without its matching `end`.",
            meta: %{line: line}
          }
        ]

      :none ->
        []
    end
  end

  @impl true
  def fix(source), do: do_fix(source)

  defp do_fix(source) do
    case detect(source) do
      {:ok, _line} -> do_fix(append_end(source))
      :none -> source
    end
  end

  # `{:ok, opening_line}` when the source fails to parse specifically because an
  # opened `do` block reached EOF without its `end`.
  defp detect(source) do
    case Code.string_to_quoted(source) do
      {:error, {meta, message, _token}} when is_list(meta) ->
        if is_binary(message) and message =~ "missing terminator: end" and
             Keyword.get(meta, :expected_delimiter) == :end do
          {:ok, Keyword.get(meta, :line)}
        else
          :none
        end

      _ ->
        :none
    end
  end

  # Append a single `end` on its own line at EOF, preserving one trailing newline.
  defp append_end(source) do
    base = if String.ends_with?(source, "\n"), do: source, else: source <> "\n"
    base <> "end\n"
  end
end
