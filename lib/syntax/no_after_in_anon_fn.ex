defmodule Credence.Syntax.NoAfterInAnonFn do
  @moduledoc """
  Detects and removes `after` clauses inside anonymous functions (`fn` blocks).

  LLMs frequently generate `after` clauses inside anonymous functions passed to
  `spawn_monitor`/`spawn_link`, but `after` is only valid inside `try`/`receive`
  blocks. This causes a syntax error ("syntax error before: 'after'"). The
  deterministic fix removes the entire `after` clause (keyword + body) and keeps
  the `fn`'s closing `end`.

  ## Bad (won't parse — syntax error at `after`)

      spawn_monitor(fn ->
        result = processor.(task)
        send(parent, {:done, result})
      after
        0 -> nil
      end)

  ## Good

      spawn_monitor(fn ->
        result = processor.(task)
        send(parent, {:done, result})
      end)
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @impl true
  def analyze(source) do
    case find_after_in_fn(source) do
      {:ok, line} ->
        [
          %Issue{
            rule: :no_after_in_anon_fn,
            message: "`after` inside anonymous function — only valid in `try`/`receive`",
            meta: %{line: line}
          }
        ]

      :none ->
        []
    end
  end

  @impl true
  def fix(source) do
    case find_after_in_fn(source) do
      {:ok, after_line} ->
        fixed = remove_after_clause(source, after_line)
        # Recurse in case of multiple occurrences (parser reports one at a time).
        if fixed != source, do: fix(fixed), else: source

      :none ->
        source
    end
  end

  # Ask the parser where (if anywhere) `after` is unexpected.  The token
  # "'after'" in the error tuple is the definitive signal — in every other
  # context (`try`, `receive`, `if`, `case`, …) the keyword is accepted.
  defp find_after_in_fn(source) do
    case Code.string_to_quoted(source, columns: true) do
      {:error, {meta, _msg, "'after'"}} when is_list(meta) ->
        {:ok, Keyword.get(meta, :line)}

      _ ->
        :none
    end
  end

  # Remove lines from `after` (inclusive) up to the `end` that closes the
  # enclosing `fn` (exclusive — the `end` line is kept).
  defp remove_after_clause(source, after_line_no) do
    lines = String.split(source, "\n")
    after_idx = after_line_no - 1

    case find_closing_end(lines, after_idx + 1) do
      nil ->
        source

      end_idx ->
        {before, rest} = Enum.split(lines, after_idx)
        Enum.join(before ++ Enum.drop(rest, end_idx - after_idx), "\n")
    end
  end

  # Walk forward from `start_idx`, tracking block nesting.  Each `do`/`fn`
  # increments; each `end` decrements.  When nesting drops below zero we've
  # found the `end` that closes the `fn` the `after` was sitting in.
  defp find_closing_end(lines, start_idx) do
    find_closing_end(lines, start_idx, 0)
  end

  defp find_closing_end(lines, idx, _nesting) when idx >= length(lines), do: nil

  defp find_closing_end(lines, idx, nesting) do
    line = Enum.at(lines, idx)
    {opens, closes} = count_block_tokens(line)

    if nesting + opens - closes < 0 do
      idx
    else
      find_closing_end(lines, idx + 1, nesting + opens - closes)
    end
  end

  # Count block-opening tokens (`do`, `fn`) and closing tokens (`end`) on a
  # line.  Word-boundary anchors prevent matching inside identifiers like
  # `send` or `render`.
  defp count_block_tokens(line) do
    opens =
      length(Regex.scan(~r/\bdo\b/, line)) + length(Regex.scan(~r/\bfn\b/, line))

    closes = length(Regex.scan(~r/\bend\b/, line))
    {opens, closes}
  end
end
