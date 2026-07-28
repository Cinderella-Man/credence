defmodule Credence.Syntax.FixBareTupleZeroInType do
  @moduledoc """
  Fixes a bare `()` before `->` in a typespec attribute.

  LLMs frequently emit `@type f :: () -> any()`. Elixir needs the function
  type wrapped in parens — `(() -> any())` — and without them the `->` is
  read as the start of a clause list, so the module stops parsing.

  ## Bad (fails to parse)

      @type task_func :: () -> any()

  ## Good

      @type task_func :: (() -> any())

  ## What is flagged

  A single line that

    * starts with `@type`, `@typep`, `@opaque`, `@spec`, `@callback` or
      `@macrocallback`,
    * has a `::` outside any brackets whose right-hand side is a bare
      `() -> <something>`, and
    * whose right-hand side is a self-contained type: brackets balanced, no
      second `::`, no `when` guard, and a plausible closing character.

  ## What is deliberately left alone

  Everything the parenthesis cannot simply be appended to at end of line,
  because there the naive wrap produces source that is still broken:

      @type t :: () -> any() # zero-arity        # `(… # zero-arity)`
      @type t :: () ->                           # `(() ->)`
      @type t :: () -> any(),                    # `(() -> any(),)`
      @spec f(x :: () -> any()) :: :ok           # tail is unbalanced
      @spec f(a) :: () -> any() when a: var      # guard belongs outside
      @type t :: () -> any() -> nil              # a second top-level arrow
      @typedoc "@type t :: () -> any()"          # quoted text, not a typespec

  A line carrying a `#`, `"` or `'` is skipped outright: the rule works on
  raw text, so it cannot tell a comment or a string literal from code, and
  wrapping through one corrupts it. Those shapes stay unflagged (see the
  analyze test) rather than being "fixed" into something that still does not
  parse.

  Lines *inside* a heredoc carry no quotes of their own, so the rule also
  tracks `\"\"\"`/`'''` delimiters and skips the body: a typespec example in
  a `@moduledoc` is prose, and rewriting it would change the documentation
  the module produces.
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  # Typespec attributes are the only place a bare `() ->` is repairable.
  @typespec_attr ~r/^\s*@(?:type|typep|opaque|spec|callback|macrocallback)\s/

  # The right-hand side must be a bare `()` arrow with an actual return type
  # after the arrow — `() ->` with nothing after it has no safe wrap.
  @bare_arrow ~r/^\s*\(\)\s*->\s*\S/

  # The tail has to end on something a type can end on, so the appended `)`
  # lands after a complete type (never after `,`, `|` or `->`).
  @type_end ~r/[\w)\]}?!]$/

  @impl true
  def analyze(source) do
    source
    |> code_lines()
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      case target(line) do
        {:ok, _prefix, _tail, _trailing} -> [build_issue(line_no)]
        :none -> []
      end
    end)
  end

  @impl true
  def fix(source) do
    source
    |> code_lines()
    |> Enum.map_join("\n", fn
      {:heredoc, line} ->
        line

      line ->
        case target(line) do
          {:ok, prefix, tail, trailing} -> "#{prefix}:: (#{tail})#{trailing}"
          :none -> line
        end
    end)
  end

  # The lines of `source`, with the ones sitting inside a heredoc tagged
  # `{:heredoc, line}` so neither callback touches them. A `@moduledoc`
  # example carries no quotes of its own, so tracking the heredoc delimiters
  # is what keeps the rule out of documentation prose.
  defp code_lines(source) do
    source
    |> String.split("\n")
    |> Enum.map_reduce(false, fn line, in_heredoc? ->
      {if(in_heredoc?, do: {:heredoc, line}, else: line), toggle_heredoc(in_heredoc?, line)}
    end)
    |> elem(0)
  end

  defp toggle_heredoc(in_heredoc?, line) do
    delimiters = count(line, ~s(""")) + count(line, ~s('''))

    if rem(delimiters, 2) == 1, do: not in_heredoc?, else: in_heredoc?
  end

  defp count(line, delimiter), do: length(String.split(line, delimiter)) - 1

  # `{:ok, prefix, tail, trailing}` when the line is a typespec attribute
  # whose top-level `::` is followed by a wrappable bare `() -> ...`.
  # `prefix` is everything before that `::` (its original spacing kept),
  # `tail` the function type, `trailing` whatever whitespace ended the line
  # (a `\r` from a CRLF file, say) so the rewrite gives it back. A heredoc
  # line is prose, never a typespec, so it is never a target.
  defp target({:heredoc, _line}), do: :none

  defp target(line) do
    with true <- Regex.match?(@typespec_attr, line),
         false <- String.contains?(line, "#"),
         false <- String.contains?(line, "\""),
         false <- String.contains?(line, "'"),
         {:ok, prefix, rest} <- split_at_separator(String.to_charlist(line)),
         [_, tail, trailing] <- Regex.run(~r/^\s*(.*?)(\s*)$/s, rest),
         true <- wrappable?(tail) do
      {:ok, prefix, tail, trailing}
    else
      _ -> :none
    end
  end

  defp wrappable?(tail) do
    balanced?(tail) and
      single_arrow?(tail) and
      not String.contains?(tail, "::") and
      not Regex.match?(~r/\bwhen\b/, tail) and
      Regex.match?(@type_end, tail)
  end

  # Splits the line at the first bracket-depth-0 `::` whose right-hand side
  # starts with a bare `() ->`. A `::` nested inside brackets (a named spec
  # argument, `f(t :: integer())`) is skipped, and a closing bracket with no
  # opener means the line is too broken to reason about.
  defp split_at_separator(chars), do: do_split(chars, 0, [])

  defp do_split([], _depth, _acc), do: :none

  defp do_split([?:, ?: | rest], 0, acc) do
    tail = List.to_string(rest)

    if Regex.match?(@bare_arrow, tail) do
      {:ok, acc |> Enum.reverse() |> List.to_string(), tail}
    else
      do_split(rest, 0, [?:, ?: | acc])
    end
  end

  defp do_split([?:, ?: | rest], depth, acc), do: do_split(rest, depth, [?:, ?: | acc])

  defp do_split([c | rest], depth, acc) when c in ~c"([{",
    do: do_split(rest, depth + 1, [c | acc])

  defp do_split([c | _rest], 0, _acc) when c in ~c")]}", do: :none

  defp do_split([c | rest], depth, acc) when c in ~c")]}",
    do: do_split(rest, depth - 1, [c | acc])

  defp do_split([c | rest], depth, acc), do: do_split(rest, depth, [c | acc])

  defp balanced?(tail) do
    tail
    |> String.to_charlist()
    |> Enum.reduce_while(0, fn
      c, depth when c in ~c"([{" -> {:cont, depth + 1}
      c, 0 when c in ~c")]}" -> {:halt, :unbalanced}
      c, depth when c in ~c")]}" -> {:cont, depth - 1}
      _c, depth -> {:cont, depth}
    end)
    |> Kernel.==(0)
  end

  # Exactly one `->` outside brackets — the function type's own arrow. A
  # nested one (`() -> (integer() -> boolean())`) is fine, but a second
  # top-level arrow (`() -> any() -> nil`) is a shape one added paren pair
  # cannot repair.
  defp single_arrow?(tail) do
    tail |> String.to_charlist() |> count_arrows(0, 0) == 1
  end

  defp count_arrows([], _depth, count), do: count
  defp count_arrows([?-, ?> | rest], 0, count), do: count_arrows(rest, 0, count + 1)

  defp count_arrows([c | rest], depth, count) when c in ~c"([{",
    do: count_arrows(rest, depth + 1, count)

  defp count_arrows([c | rest], depth, count) when c in ~c")]}",
    do: count_arrows(rest, depth - 1, count)

  defp count_arrows([_c | rest], depth, count), do: count_arrows(rest, depth, count)

  defp build_issue(line_no) do
    %Issue{
      rule: :fix_bare_tuple_zero_in_type,
      message:
        "Bare `()` before `->` in a typespec is ambiguous and fails to parse. " <>
          "Wrap the function type in parens: `(() -> ...)`.",
      meta: %{line: line_no}
    }
  end
end
