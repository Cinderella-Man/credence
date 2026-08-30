defmodule Credence.Syntax.FixKeywordBeforePositionalArgument do
  @moduledoc """
  Fixes the syntax error where keyword arguments appear before positional
  arguments in a function call.

  LLMs frequently generate code like:

      Task.Supervisor.start_link(name: __MODULE__, [])

  In Elixir, keyword lists must always come as the last argument. When a
  keyword-style argument (`key: value`) precedes a positional argument, the
  parser rejects it with:

      "unexpected expression after keyword list.
       Keyword lists must always come as the last argument."

  The fix reorders the arguments so all keyword arguments are moved to the end
  of the argument list, preserving the relative order within each group
  (positional and keyword).

  ## Bad (won't parse)

      Task.Supervisor.start_link(name: __MODULE__, [])
      foo(key1: 1, key2: 2, positional)

  ## Good

      Task.Supervisor.start_link([], name: __MODULE__)
      foo(positional, key1: 1, key2: 2)

  ## The safe core

  The offending call is located textually (the source does not parse, so there
  is no AST to work from) and its arguments are split on top-level commas. A
  purely textual split is only trustworthy while the argument text contains no
  construct that can hide a comma or a bracket from it, so the rule **declines
  to fix** — `analyze/1` stays silent too — whenever the argument text contains
  any of `"`, `'`, `#`, `~`, `?`, `\\` or `->` (strings, charlists, comments,
  sigils, char literals, escapes, `fn`/`case` clauses).

  Without that guard the split runs straight through a string literal and the
  rejoin silently produces a *different, parseable* program:

      foo(a: ",", b)   would become   foo(", b, a: ")

  Two further checks make sure the located call is really the broken one and
  that the rewrite actually repairs it: the original argument text, wrapped in
  a dummy call, must fail to parse with this very error, and the reordered
  argument text, wrapped the same way, must parse.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue
  alias Credence.SourceMask

  @error_fragment "unexpected expression after keyword list"

  # Characters/tokens that can hide a comma or bracket from a textual split.
  @unsafe_in_args ["\"", "'", "#", "~", "?", "\\", "->"]

  @impl true
  def analyze(source) do
    case rewrite(source) do
      {:ok, line, message, _fixed} ->
        [
          %Issue{
            rule: :fix_keyword_before_positional_argument,
            message: message,
            meta: %{line: line}
          }
        ]

      :none ->
        []
    end
  end

  @impl true
  def fix(source), do: run(source)

  defp run(source) do
    case rewrite(source) do
      {:ok, _line, _message, fixed} when fixed != source -> run(fixed)
      _ -> source
    end
  end

  # The single decision point shared by `analyze/1` and `fix/1`, so the check
  # never flags a case the fix would not touch.
  defp rewrite(source) do
    with {:error, {meta, msg, _token}} <- Code.string_to_quoted(source),
         true <- is_list(meta),
         message = message_to_string(msg),
         true <- String.contains?(message, @error_fragment),
         {:ok, fixed} <- reorder(source, meta) do
      {:ok, Keyword.get(meta, :line), message, fixed}
    else
      _ -> :none
    end
  end

  # A parse error carries either a binary message or an `{opening, hint}` tuple
  # (e.g. "unexpected reserved word"); `to_string/1` raises on the tuple.
  defp message_to_string(msg) when is_binary(msg), do: msg

  defp message_to_string({opening, hint}) when is_binary(opening) and is_binary(hint),
    do: opening <> hint

  defp message_to_string(other), do: inspect(other)

  defp reorder(source, meta) do
    line = Keyword.get(meta, :line, 1)
    col = Keyword.get(meta, :column, 1)

    with {:ok, error_pos} <- SourceMask.byte_offset(source, line, col),
         {:ok, open_pos} <- find_open_paren(source, error_pos, 0),
         {:ok, close_pos} <- find_close_paren(source, open_pos + 1, 0),
         args_text = binary_part(source, open_pos + 1, close_pos - open_pos - 1),
         false <- String.contains?(args_text, @unsafe_in_args),
         args = split_args(args_text),
         {[_ | _] = positional, [_ | _] = keyword} <- separate_args(args),
         true <- keyword_before_positional?(args),
         new_args = Enum.join(positional ++ keyword, ", "),
         true <- broken_call?(args_text),
         true <- valid_call?(new_args) do
      prefix = binary_part(source, 0, open_pos + 1)
      suffix = binary_part(source, close_pos, byte_size(source) - close_pos)
      {:ok, prefix <> new_args <> suffix}
    else
      _ -> :error
    end
  end

  # The argument text on its own must be broken by *this* error — proof that the
  # call we located textually is the one the parser choked on.
  defp broken_call?(args_text) do
    case Code.string_to_quoted(wrap(args_text)) do
      {:error, {_meta, msg, _token}} -> String.contains?(message_to_string(msg), @error_fragment)
      _ -> false
    end
  end

  # ...and the reordered argument text must parse — proof the rewrite repairs it.
  defp valid_call?(args_text), do: match?({:ok, _}, Code.string_to_quoted(wrap(args_text)))

  defp wrap(args_text), do: "credence_probe(" <> args_text <> ")"

  # Walk backward from `pos` to the nearest "(" at nesting depth 0. Scanning
  # bytes is safe: a UTF-8 continuation byte is never an ASCII paren.
  defp find_open_paren(_source, pos, _depth) when pos < 0, do: :error

  defp find_open_paren(source, pos, depth) when pos >= byte_size(source),
    do: find_open_paren(source, byte_size(source) - 1, depth)

  defp find_open_paren(source, pos, depth) do
    case :binary.at(source, pos) do
      ?) -> find_open_paren(source, pos - 1, depth + 1)
      ?( when depth > 0 -> find_open_paren(source, pos - 1, depth - 1)
      ?( -> {:ok, pos}
      _ -> find_open_paren(source, pos - 1, depth)
    end
  end

  # Find the ")" matching an opening "(" , starting just after it.
  defp find_close_paren(source, pos, _depth) when pos >= byte_size(source), do: :error

  defp find_close_paren(source, pos, depth) do
    case :binary.at(source, pos) do
      ?( -> find_close_paren(source, pos + 1, depth + 1)
      ?) when depth > 0 -> find_close_paren(source, pos + 1, depth - 1)
      ?) -> {:ok, pos}
      _ -> find_close_paren(source, pos + 1, depth)
    end
  end

  # Separate args into positional and keyword groups, preserving relative order.
  defp separate_args(args) do
    {Enum.reject(args, &keyword_arg?/1), Enum.filter(args, &keyword_arg?/1)}
  end

  # True when some keyword arg is followed by a positional one — the shape the
  # parser rejects.
  defp keyword_before_positional?(args) do
    args
    |> Enum.drop_while(&(not keyword_arg?(&1)))
    |> Enum.any?(&(not keyword_arg?(&1)))
  end

  # A keyword argument has the form `key: value` — it starts with a lowercase
  # identifier or underscore-prefixed name followed immediately by `:`.
  @keyword_start ~r/^[\p{Ll}_][\p{L}\p{N}_?!]*:/u

  defp keyword_arg?(arg), do: Regex.match?(@keyword_start, String.trim(arg))

  # Split argument text into individual arguments, respecting bracket nesting.
  defp split_args(text) do
    text
    |> String.to_charlist()
    |> do_split_args([], [], 0)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp do_split_args([], current, acc, _depth) do
    Enum.reverse([current |> Enum.reverse() |> List.to_string() | acc])
  end

  defp do_split_args([?, | rest], current, acc, 0) do
    do_split_args(rest, [], [current |> Enum.reverse() |> List.to_string() | acc], 0)
  end

  defp do_split_args([ch | rest], current, acc, depth) when ch in [?\(, ?\[, ?{] do
    do_split_args(rest, [ch | current], acc, depth + 1)
  end

  defp do_split_args([ch | rest], current, acc, depth) when ch in [?\), ?\], ?}] do
    do_split_args(rest, [ch | current], acc, depth - 1)
  end

  defp do_split_args([ch | rest], current, acc, depth) do
    do_split_args(rest, [ch | current], acc, depth)
  end
end
