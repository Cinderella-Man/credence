defmodule Credence.Syntax.NoMarkdownCodeFences do
  @moduledoc """
  Removes the markdown code-fence lines that wrap generated Elixir source.

  LLMs frequently wrap their answer in a markdown code fence — a line that is
  nothing but three backticks (U+0060×3), optionally with a language tag like
  `elixir`. Such a line is never valid Elixir, so the wrapped module fails to
  parse. This is a REPAIR: strip the wrapping fence lines.

  ## Why only the wrapping fences

  A fence line can also appear legitimately *inside* a `@moduledoc`/`@doc`
  heredoc (documentation that shows a fenced code block). Because the syntax
  phase runs every rule's `fix` whenever the source fails to parse for *any*
  reason, a rule that stripped every fence-shaped line would corrupt those
  in-docstring fences when some unrelated part of the file fails to parse.

  Two guards keep the repair to the genuine bug:

    * **Anchor** — only the file's first and last non-blank lines are eligible.
      A docstring fence sits between `defmodule … do`/an attribute and the
      closing `end`, so it is never the first or last non-blank line and is
      never touched.
    * **Parse gate** — the stripped result is committed only when it then
      parses. If the file was unparseable for an unrelated reason, stripping a
      wrapping fence cannot fix it, so the result still fails to parse and the
      original is returned unchanged.

  ## Bad (won't parse)

      ```elixir
      defmodule Solution do
        def hello, do: :world
      end
      ```

  ## Good

      defmodule Solution do
        def hello, do: :world
      end
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  # A standalone markdown code-fence line: optional surrounding whitespace, three
  # backticks, an optional language tag, nothing else. Never valid Elixir.
  @fence_pattern ~r/^\s*```\s*[\w-]*\s*$/

  @impl true
  def analyze(source) do
    case repair(source) do
      {:fixed, _fixed, dropped} ->
        Enum.map(dropped, fn idx ->
          %Issue{
            rule: :no_markdown_code_fences,
            message: "Markdown code-fence line will cause a syntax error.",
            meta: %{line: idx + 1}
          }
        end)

      :no_fix ->
        []
    end
  end

  @impl true
  def fix(source) do
    case repair(source) do
      {:fixed, fixed, _dropped} -> fixed
      :no_fix -> source
    end
  end

  # Strip the wrapping fence lines (first and/or last non-blank line) and commit
  # only when the result parses. analyze and fix share this helper so they agree.
  defp repair(source) do
    if parses?(source) do
      :no_fix
    else
      lines = String.split(source, "\n")
      indexed = Enum.with_index(lines)
      nonblank = Enum.filter(indexed, fn {line, _idx} -> String.trim(line) != "" end)

      case nonblank do
        [] ->
          :no_fix

        _ ->
          {_, first_idx} = List.first(nonblank)
          {_, last_idx} = List.last(nonblank)

          dropped =
            [first_idx, last_idx]
            |> Enum.uniq()
            |> Enum.filter(fn idx -> Regex.match?(@fence_pattern, Enum.at(lines, idx)) end)

          commit(source, indexed, dropped)
      end
    end
  end

  defp commit(_source, _indexed, []), do: :no_fix

  defp commit(source, indexed, dropped) do
    kept =
      indexed
      |> Enum.reject(fn {_line, idx} -> idx in dropped end)
      |> Enum.map_join("\n", &elem(&1, 0))

    if kept != source and parses?(kept) do
      {:fixed, kept, dropped}
    else
      :no_fix
    end
  end

  defp parses?(source), do: match?({:ok, _}, Code.string_to_quoted(source))
end
