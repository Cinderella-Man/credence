defmodule Credence.Syntax.CloseUnclosedFnDelimiter do
  @moduledoc """
  Detects and fixes unclosed `fn` delimiters where the LLM writes
  `end)` (closing an inner block + the fn-call paren) without the
  matching `end` that should close the `fn` itself.

  LLMs frequently produce code like:

      Enum.map(row, fn element ->
        if element == 0 do min_value else element end)
      end

  where the `end` closes the `if` block and `)` closes the `Enum.map`
  call, but the `fn` body is never closed. The fix inserts the missing
  `end` before the closing paren and removes the stray `end` that the
  LLM placed on the next line (which was intended to close the fn but
  no longer has a block to close):

      Enum.map(row, fn element ->
        if element == 0 do min_value else element end end)
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @end_paren ~r/end\)+$/
  @only_end ~r/^\s*end\s*$/

  @impl true
  def analyze(source) do
    lines = String.split(source, "\n")

    {_stack, issues} =
      Enum.reduce(Enum.with_index(lines, 1), {[], []}, fn {line, line_no}, {stack, acc} ->
        fn_in_stack = Enum.any?(stack, &(&1 == :fn))
        tokens = tokenize_line(line)
        {new_stack, last_popped} = apply_tokens(tokens, stack)

        issue =
          if fn_in_stack and last_popped != :fn and Regex.match?(@end_paren, line) do
            [
              %Issue{
                rule: :close_unclosed_fn_delimiter,
                message: "Unclosed `fn` delimiter — the `fn` body is not closed before `)`.",
                meta: %{line: line_no}
              }
            ]
          else
            []
          end

        {new_stack, acc ++ issue}
      end)

    issues
  end

  @impl true
  def fix(source) do
    lines = String.split(source, "\n")
    do_fix(lines, [], [])
  end

  defp do_fix([], acc, _stack), do: Enum.join(Enum.reverse(acc), "\n")

  defp do_fix([line | rest], acc, stack) do
    fn_in_stack = Enum.any?(stack, &(&1 == :fn))
    fn_count = Enum.count(stack, &(&1 == :fn))
    tokens = tokenize_line(line)
    {_, last_popped} = apply_tokens(tokens, stack)

    if fn_in_stack and last_popped != :fn and Regex.match?(@end_paren, line) do
      num_ends = min(fn_count, count_trailing_parens(line))
      fixed = insert_ends(line, num_ends)
      fixed_tokens = tokenize_line(fixed)
      {new_stack, _} = apply_tokens(fixed_tokens, stack)

      # If the next line is a stray `end` (was intended to close the fn
      # that we just closed), skip it.
      case rest do
        [next_line | rest_rest] ->
          if Regex.match?(@only_end, next_line) do
            do_fix(rest_rest, [fixed | acc], new_stack)
          else
            do_fix(rest, [fixed | acc], new_stack)
          end

        _ ->
          do_fix(rest, [fixed | acc], new_stack)
      end
    else
      new_stack = apply_tokens(tokens, stack) |> elem(0)
      do_fix(rest, [line | acc], new_stack)
    end
  end

  # Extract block-opening/closing tokens in order from a line.
  defp tokenize_line(line) do
    ~r/\bfn\b|\bdo\b(?!:)|\bend\b/
    |> Regex.scan(line, return: :index)
    |> Enum.map(fn [{pos, _len}] ->
      case String.at(line, pos) do
        "f" -> :fn
        "d" -> :do
        "e" -> :end
      end
    end)
  end

  # Apply tokens to the stack, returning {new_stack, last_popped_type}.
  defp apply_tokens(tokens, stack) do
    Enum.reduce(tokens, {stack, nil}, fn
      :fn, {s, _} -> {[:fn | s], nil}
      :do, {s, _} -> {[:do | s], nil}
      :end, {[popped | rest], _} -> {rest, popped}
      :end, {[], _} -> {[], nil}
    end)
  end

  defp count_trailing_parens(line) do
    case Regex.run(~r/(\)+)\s*$/, line) do
      [_, parens] -> String.length(parens)
      _ -> 0
    end
  end

  defp insert_ends(line, num_ends) do
    extra = String.duplicate(" end", num_ends)

    Regex.replace(
      ~r/(\bend)(\))+/,
      line,
      fn _full, end_word, parens ->
        end_word <> extra <> parens
      end, global: false)
  end
end
