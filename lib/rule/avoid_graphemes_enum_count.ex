defmodule Credence.Rule.AvoidGraphemesEnumCount do
  @moduledoc """
  Performance rule: Detects the use of `Enum.count/1` or `Enum.count/2` on
  the result of `String.graphemes/1`.

  Calling `String.graphemes/1` eagerly allocates a list containing every
  grapheme in the string. If your goal is simply to count the characters,
  `String.length/1` accomplishes this without the intermediate list allocation.

  If you are counting characters that match a specific condition (using
  `Enum.count/2`), you can avoid allocating the entire list in memory by
  using a lazy stream backed by `String.next_grapheme/1`.

  ## Bad

      # Counting all characters
      string
      |> String.graphemes()
      |> Enum.count()

      # Counting characters with a predicate
      string
      |> String.graphemes()
      |> Enum.count(fn char -> char == "a" end)

  ## Good

      # Counting all characters
      String.length(string)

      # Or in a pipeline:
      string
      |> String.length()

      # Counting characters with a predicate
      string
      |> Stream.unfold(&String.next_grapheme/1)
      |> Enum.count(fn char -> char == "a" end)
  """

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipe form: ... |> Enum.count() / ... |> Enum.count(pred)
        {:|>, meta, [lhs, rhs]} = node, issues ->
          cond do
            enum_count_with_arity?(rhs, 0) and immediate_graphemes?(lhs) ->
              {node, [length_issue(meta) | issues]}

            enum_count_with_arity?(rhs, 1) and immediate_graphemes?(lhs) ->
              {node, [stream_unfold_issue(meta) | issues]}

            true ->
              {node, issues}
          end

        # Direct: Enum.count(String.graphemes(...))
        {{:., meta, [{:__aliases__, _, [:Enum]}, :count]}, _, [arg]} = node, issues ->
          if graphemes_call?(arg) do
            {node, [length_issue(meta) | issues]}
          else
            {node, issues}
          end

        # Direct: Enum.count(String.graphemes(...), pred)
        {{:., meta, [{:__aliases__, _, [:Enum]}, :count]}, _, [arg, _pred]} = node, issues ->
          if graphemes_call?(arg) do
            {node, [stream_unfold_issue(meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      # ── Pipe forms ──

      {:|>, _, [lhs, rhs]} = node when is_tuple(rhs) ->
        cond do
          enum_count_with_arity?(rhs, 0) and immediate_graphemes?(lhs) ->
            fix_no_predicate_pipe(lhs)

          enum_count_with_arity?(rhs, 1) and immediate_graphemes?(lhs) ->
            fix_predicate_pipe(lhs, rhs)

          true ->
            node
        end

      # ── Direct forms ──

      # Enum.count(String.graphemes(x)) → String.length(x)
      {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, [arg]} = node ->
        case extract_graphemes_arg(arg) do
          {:ok, subject} -> string_length_call(subject)
          :error -> node
        end

      # Enum.count(String.graphemes(x), pred) → Enum.count(Stream.unfold(...), pred)
      {{:., dot_meta, [{:__aliases__, _, [:Enum]}, :count]}, call_meta, [arg, pred]} = node ->
        case extract_graphemes_arg(arg) do
          {:ok, subject} ->
            {{:., dot_meta, [{:__aliases__, [], [:Enum]}, :count]}, call_meta,
             [grapheme_stream(subject), pred]}

          :error ->
            node
        end

      node ->
        node
    end)
    |> Sourceror.to_string()
  end

  # ── Fix: no-predicate pipe ─────────────────────────────────────────

  # String.graphemes(x) |> Enum.count() → String.length(x)
  defp fix_no_predicate_pipe({{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, [subject]}) do
    string_length_call(subject)
  end

  # x |> String.graphemes() |> Enum.count() → x |> String.length()
  defp fix_no_predicate_pipe(
         {:|>, pipe_meta, [deeper, {{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, _}]}
       ) do
    {:|>, pipe_meta, [deeper, {{:., [], [{:__aliases__, [], [:String]}, :length]}, [], []}]}
  end

  defp fix_no_predicate_pipe(lhs), do: lhs

  # ── Fix: predicate pipe ────────────────────────────────────────────

  # String.graphemes(x) |> Enum.count(pred) → Stream.unfold(x, &...) |> Enum.count(pred)
  defp fix_predicate_pipe(
         {{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, [subject]},
         rhs
       ) do
    {:|>, [], [grapheme_stream(subject), rhs]}
  end

  # x |> String.graphemes() |> Enum.count(pred) → x |> Stream.unfold(&...) |> Enum.count(pred)
  defp fix_predicate_pipe(
         {:|>, pipe_meta, [deeper, {{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, _}]},
         rhs
       ) do
    unfold_step =
      {{:., [], [{:__aliases__, [], [:Stream]}, :unfold]}, [], [next_grapheme_capture()]}

    {:|>, [], [{:|>, pipe_meta, [deeper, unfold_step]}, rhs]}
  end

  defp fix_predicate_pipe(lhs, rhs), do: {:|>, [], [lhs, rhs]}

  # ── AST builders ───────────────────────────────────────────────────

  defp string_length_call(subject) do
    {{:., [], [{:__aliases__, [], [:String]}, :length]}, [], [subject]}
  end

  # Stream.unfold(subject, &String.next_grapheme/1)
  defp grapheme_stream(subject) do
    {{:., [], [{:__aliases__, [], [:Stream]}, :unfold]}, [], [subject, next_grapheme_capture()]}
  end

  # &String.next_grapheme/1
  defp next_grapheme_capture do
    {:&, [],
     [
       {:/, [],
        [
          {{:., [], [{:__aliases__, [], [:String]}, :next_grapheme]}, [no_parens: true], []},
          1
        ]}
     ]}
  end

  # ── Shared detection helpers ───────────────────────────────────────

  defp extract_graphemes_arg({{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, [subject]}),
    do: {:ok, subject}

  defp extract_graphemes_arg(_), do: :error

  defp enum_count_with_arity?({{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, args}, arity)
       when is_list(args),
       do: length(args) == arity

  defp enum_count_with_arity?(_, _), do: false

  defp immediate_graphemes?({:|>, _, [_, rhs]}), do: graphemes_call?(rhs)
  defp immediate_graphemes?(other), do: graphemes_call?(other)

  defp graphemes_call?({{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, args})
       when is_list(args),
       do: true

  defp graphemes_call?(_), do: false

  # ── Issue builders ─────────────────────────────────────────────────

  defp length_issue(meta) do
    %Issue{
      rule: :avoid_graphemes_enum_count,
      message: """
      Use `String.length/1` instead of `Enum.count(String.graphemes(...))`.

      Counting graphemes via `Enum.count/1` forces allocation of an
      intermediate list, while `String.length/1` avoids this.
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp stream_unfold_issue(meta) do
    %Issue{
      rule: :avoid_graphemes_enum_count,
      message: """
      Avoid `String.graphemes/1 |> Enum.count/2` — it allocates an
      intermediate list of all graphemes just to count the ones that
      match the predicate.

      Use a lazy stream instead:

          Stream.unfold(string, &String.next_grapheme/1)
          |> Enum.count(predicate)

      This avoids building the grapheme list entirely.
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
