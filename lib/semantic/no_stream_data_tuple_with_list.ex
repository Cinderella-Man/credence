defmodule Credence.Semantic.NoStreamDataTupleWithList do
  @moduledoc """
  Repairs calls to `StreamData.tuple/1` whose argument is a list literal
  (`[gen1, gen2]`) instead of a tuple (`{gen1, gen2}`).

  `StreamData.tuple/1` only accepts a tuple of generators, so a list argument
  is a guaranteed `FunctionClauseError` at runtime. The type checker flags it
  at compile time:

      "incompatible types given to StreamData.tuple/1:

           StreamData.tuple([key_gen, value_gen])

       given types:

           -dynamic(non_empty_list(%StreamData{...}))-

       but expected one of:

           {...}"

  The fix swaps the argument's brackets: `StreamData.tuple([a, b])` becomes
  `StreamData.tuple({a, b})`. Only the two bracket characters are rewritten —
  every byte between them (element order, side effects, comments, line breaks)
  survives, and because the patch is the same length as the text it replaces,
  the positions of every other diagnostic in the same pass stay valid.

  ## What is deliberately left alone

  The message is emitted for *any* wrongly-typed argument, so the rule only
  rewrites the cases where the bracket swap provably re-parses as the tuple
  the author asked for:

    * the call is anchored at the diagnostic's line *and* column, so another
      `tuple/1` call elsewhere in the file is never touched. Both spellings
      the checker reports this way are handled: qualified
      (`StreamData.tuple(...)`) and imported (`tuple(...)` under
      `import StreamData` / `use ExUnitProperties`) — the diagnostic itself
      is what proves the call at that position resolves to `StreamData.tuple/1`.
    * the argument must be a *list literal in the source*: a variable holding
      a list (`StreamData.tuple(gens)`), a concatenation
      (`StreamData.tuple([a] ++ b)`), a charlist sigil and every non-list
      argument (`StreamData.tuple(:foo)`) no-op, because there are no brackets
      to swap and any repair would have to invent code.
    * a cons cell (`[a | b]`) is skipped: `{a | b}` parses as a one-element
      tuple holding a misplaced `|` rather than as an error, so it is the one
      swap that would silently mean something else.
    * the patched source must still parse. That rejects keyword-list arguments
      (`[a: gen]` — `{a: gen}` is a syntax error, "unexpected keyword list
      inside tuple") and anything else the tuple container refuses.

  The `should_report?/2` phase hook keeps `analyze` honest by reporting an
  issue only when `fix/2` would actually rewrite the source.

  ## Bad

      defmodule CredenceTupleWithListFlagshipCheckNSDTWL do
        @moduledoc false

        def object do
          key_gen = StreamData.string(:alphanumeric, min_length: 1, max_length: 8)
          value_gen = StreamData.integer()

          StreamData.list_of(
            StreamData.tuple([key_gen, value_gen]),
            max_length: 5
          )
          |> StreamData.map(&Map.new/1)
        end
      end

  ## Good

      defmodule CredenceTupleWithListFlagshipCheckNSDTWL do
        @moduledoc false

        def object do
          key_gen = StreamData.string(:alphanumeric, min_length: 1, max_length: 8)
          value_gen = StreamData.integer()

          StreamData.list_of(
            StreamData.tuple({key_gen, value_gen}),
            max_length: 5
          )
          |> StreamData.map(&Map.new/1)
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "incompatible types given to StreamData.tuple/1"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

  @doc """
  Phase hook (`Credence.Semantic.match_rules/2`): report an issue only when
  `fix/2` would actually rewrite the source. The same message is emitted for
  every badly-typed `StreamData.tuple/1` argument, most of which this rule
  leaves alone.
  """
  def should_report?(diagnostic, source), do: fix(source, diagnostic) != source

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_stream_data_tuple_with_list,
      message: "StreamData.tuple/1 expects a tuple of generators, not a list — use {gen1, gen2}",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    with {line_no, col} when is_integer(line_no) <- position(diagnostic),
         {:ok, ast} <- Sourceror.parse_string(source),
         {:ok, list_node} <- flagged_list_arg(ast, {line_no, col}),
         {:ok, patch} <- bracket_patch(source, list_node),
         patched when is_binary(patched) <- Sourceror.patch_string(source, [patch]),
         true <- parses?(patched) do
      patched
    else
      _ -> source
    end
  end

  # The list literal passed to the one-argument `tuple` call whose own name
  # token starts at the diagnostic's line/column. Without a column, a lone
  # candidate on the flagged line is unambiguous; anything else no-ops rather
  # than guess.
  defp flagged_list_arg(ast, {line_no, col}) do
    {_, found} =
      Macro.prewalk(ast, [], fn
        {{:., _, [_, :tuple]}, meta, [arg]} = node, acc ->
          {node, collect(acc, meta, {line_no, col}, arg)}

        {:tuple, meta, [arg]} = node, acc ->
          {node, collect(acc, meta, {line_no, col}, arg)}

        node, acc ->
          {node, acc}
      end)

    case found do
      [list_node] -> {:ok, list_node}
      _ -> :error
    end
  end

  defp collect(acc, meta, {line_no, col}, arg) do
    if meta[:line] == line_no and (col == nil or meta[:column] == col) and list_literal?(arg) do
      [arg | acc]
    else
      acc
    end
  end

  # A list literal written out in the source, with no cons cell at the top
  # level. Sourceror wraps container literals in a `:__block__` node.
  defp list_literal?({:__block__, _, [elements]}) when is_list(elements) do
    not Enum.any?(elements, &match?({:|, _, _}, &1))
  end

  defp list_literal?(_), do: false

  # Replace the argument's span with the same text under `{}` instead of `[]`.
  # The slice must really start and end with brackets — a charlist sigil parses
  # as a list too, and has none to swap.
  defp bracket_patch(source, list_node) do
    with %{start: [line: sl, column: sc], end: [line: el, column: ec]} <-
           Sourceror.get_range(list_node),
         text when is_binary(text) <- slice(source, {sl, sc}, {el, ec}),
         true <- String.starts_with?(text, "[") and String.ends_with?(text, "]") do
      inner = String.slice(text, 1, String.length(text) - 2)

      {:ok,
       %{
         range: %{start: [line: sl, column: sc], end: [line: el, column: ec]},
         change: "{" <> inner <> "}",
         # The change *is* the original text with its brackets swapped, so
         # Sourceror's indentation correction would only re-indent lines that
         # are already correctly indented.
         preserve_indentation: false
       }}
    else
      _ -> :error
    end
  end

  defp parses?(source), do: match?({:ok, _}, Sourceror.parse_string(source))

  defp slice(source, {l1, c1}, {l2, c2}) when l1 == l2 do
    source
    |> String.split("\n")
    |> Enum.at(l1 - 1, "")
    |> String.slice(c1 - 1, max(c2 - c1, 0))
  end

  defp slice(source, {l1, c1}, {l2, c2}) when l2 > l1 do
    lines = String.split(source, "\n")
    first = lines |> Enum.at(l1 - 1, "") |> String.slice((c1 - 1)..-1//1)
    middle = Enum.slice(lines, l1..(l2 - 2)//1)
    last = lines |> Enum.at(l2 - 1, "") |> String.slice(0, c2 - 1)

    Enum.join([first] ++ middle ++ [last], "\n")
  end

  defp slice(_source, _from, _to), do: :error

  defp position(%{position: {line, col}}) when is_integer(line), do: {line, col}
  defp position(%{position: line}) when is_integer(line), do: {line, nil}
  defp position(_), do: {nil, nil}

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
