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
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @error_fragment "unexpected expression after keyword list"

  @impl true
  def analyze(source) do
    case Code.string_to_quoted(source) do
      {:error, {meta, msg, _token}} when is_list(meta) ->
        if String.contains?(to_string(msg), @error_fragment) do
          [
            %Issue{
              rule: :fix_keyword_before_positional_argument,
              message: to_string(msg),
              meta: %{line: Keyword.get(meta, :line)}
            }
          ]
        else
          []
        end

      _ ->
        []
    end
  end

  @impl true
  def fix(source) do
    case Code.string_to_quoted(source) do
      {:error, {meta, msg, _token}} when is_list(meta) ->
        if String.contains?(to_string(msg), @error_fragment) do
          fixed = do_fix(source, meta)
          if fixed == source, do: source, else: fix(fixed)
        else
          source
        end

      _ ->
        source
    end
  end

  defp do_fix(source, meta) do
    error_line = Keyword.get(meta, :line, 1)
    error_col = Keyword.get(meta, :column, 1)

    # Convert line/col (1-indexed) to a 0-indexed position in the string
    error_pos = line_col_to_pos(source, error_line, error_col)

    # Walk backward from error position to find the opening "(" of the
    # function call that has the keyword-before-positional problem.
    with {:ok, open_pos} <- find_open_paren(source, error_pos),
         {:ok, close_pos} <- find_close_paren(source, open_pos + 1) do
      # Extract the argument text between ( and )
      args_text = binary_part(source, open_pos + 1, close_pos - open_pos - 1)
      args = split_args(args_text)

      if length(args) > 1 do
        {positional, keyword} = separate_args(args)

        has_positional_after_keyword? =
          args
          |> Enum.with_index()
          |> Enum.any?(fn {arg, idx} ->
            keyword_arg?(arg) and
              Enum.any?(Enum.drop(args, idx + 1), &(not keyword_arg?(&1)))
          end)

        if has_positional_after_keyword? and positional != [] and keyword != [] do
          new_args = Enum.join(positional ++ keyword, ", ")
          # Replace args in source
          before = binary_part(source, 0, open_pos + 1)
          after_ = binary_part(source, close_pos, byte_size(source) - close_pos)
          before <> new_args <> after_
        else
          source
        end
      else
        source
      end
    else
      _ -> source
    end
  end

  # Convert 1-indexed line/column to 0-indexed byte position in string.
  defp line_col_to_pos(source, line, col) do
    source
    |> String.split("\n")
    |> Enum.take(line - 1)
    |> Enum.map(&byte_size/1)
    |> Enum.reduce(0, &(&1 + &2 + 1))  # +1 for the newline
    |> Kernel.+(col - 1)
  end

  # Walk backward from `pos` (0-indexed) to find the nearest "(" at nesting
  # depth 0 (not inside any other parens/brackets).
  defp find_open_paren(source, pos) do
    do_find_open(source, pos, 0)
  end

  defp do_find_open(_source, pos, _depth) when pos < 0, do: :error

  defp do_find_open(source, pos, depth) do
    <<_::binary-size(pos), char::utf8, _::binary>> = source

    case char do
      ?\) ->
        do_find_open(source, pos - 1, depth + 1)

      ?\( ->
        if depth > 0 do
          do_find_open(source, pos - 1, depth - 1)
        else
          {:ok, pos}
        end

      _ ->
        do_find_open(source, pos - 1, depth)
    end
  end

  # Find the matching ")" starting after an opening "(" at `pos` (0-indexed).
  defp find_close_paren(source, pos) do
    do_find_close(source, pos, 0)
  end

  defp do_find_close(source, pos, _depth) when pos >= byte_size(source), do: :error

  defp do_find_close(source, pos, depth) do
    <<_::binary-size(pos), char::utf8, _::binary>> = source

    case char do
      ?\( ->
        do_find_close(source, pos + 1, depth + 1)

      ?\) ->
        if depth > 0 do
          do_find_close(source, pos + 1, depth - 1)
        else
          {:ok, pos}
        end

      _ ->
        do_find_close(source, pos + 1, depth)
    end
  end

  # Separate args into positional and keyword groups, preserving relative order.
  defp separate_args(args) do
    positional = Enum.filter(args, &(not keyword_arg?(&1)))
    keyword = Enum.filter(args, &keyword_arg?(&1))
    {positional, keyword}
  end

  # A keyword argument has the form `key: value` — it starts with a lowercase
  # identifier or underscore-prefixed name followed immediately by `:`.
  @keyword_start ~r/^[a-z_][a-zA-Z0-9_?!]*:/

  defp keyword_arg?(arg) do
    Regex.match?(@keyword_start, String.trim(arg))
  end

  # Split argument text into individual arguments, respecting nesting.
  defp split_args(text) do
    text
    |> String.to_charlist()
    |> do_split_args([], [], 0)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp do_split_args([], current, acc, _depth) do
    Enum.reverse([Enum.reverse(current) |> List.to_string() | acc])
  end

  defp do_split_args([?, | rest], current, acc, 0) do
    do_split_args(rest, [], [Enum.reverse(current) |> List.to_string() | acc], 0)
  end

  defp do_split_args([?\( | rest], current, acc, depth) do
    do_split_args(rest, [?\( | current], acc, depth + 1)
  end

  defp do_split_args([?\) | rest], current, acc, depth) do
    do_split_args(rest, [?\) | current], acc, depth - 1)
  end

  defp do_split_args([?\[ | rest], current, acc, depth) do
    do_split_args(rest, [?\[ | current], acc, depth + 1)
  end

  defp do_split_args([?\] | rest], current, acc, depth) do
    do_split_args(rest, [?\] | current], acc, depth - 1)
  end

  defp do_split_args([?{ | rest], current, acc, depth) do
    do_split_args(rest, [?{ | current], acc, depth + 1)
  end

  defp do_split_args([?} | rest], current, acc, depth) do
    do_split_args(rest, [?} | current], acc, depth - 1)
  end

  defp do_split_args([ch | rest], current, acc, depth) do
    do_split_args(rest, [ch | current], acc, depth)
  end
end
