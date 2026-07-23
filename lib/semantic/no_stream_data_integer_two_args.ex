defmodule Credence.Semantic.NoStreamDataIntegerTwoArgs do
  @moduledoc """
  Fixes the compile error for the hallucinated two-argument `integer(min, max)`
  StreamData generator.

  StreamData exports `integer/0` and `integer/1`; the bounded generator takes a
  single `Range`, so an `import StreamData` call written as `integer(0, 10)`
  (LLMs reach for it from Python's `random.randint(0, 10)`) is a hard compile
  error whose position points at the call:

      "undefined function integer/2 (expected M to define such a function or
      for it to be imported, but none are available)"

  The fix replaces the comma between the two arguments with `..`, so
  `integer(0, 10)` becomes `integer(0..10)`. Only the punctuation between the
  arguments is rewritten — the argument text and every other byte of the file
  survive.

  ## What is deliberately left alone

  The message is emitted for *any* undefined local `integer/2`, so the rule
  only rewrites the cases where `integer(min..max)` is unambiguously the
  intended call and the rewrite provably re-parses the same way:

    * StreamData must be imported *in lexical scope at the flagged call*
      (`import StreamData`, or `use ExUnitProperties`, which imports it).
      Without it an undefined `integer/2` means something else entirely and the
      range rewrite would neither compile nor be what the author meant, so a
      sibling module in the same file that never imported StreamData keeps its
      own `integer(a, b)` call.
    * both arguments must be an integer literal (optionally negated) or a bare
      variable. `..` binds looser than `|>`, `in`, `and`, comparisons and `=`,
      so `integer(x |> f(), y)` would re-associate into `x |> (f()..y)`;
      rather than sprinkle parentheses, anything outside the safe set no-ops.
    * the text between the arguments must be a bare comma and whitespace — a
      comment parked there (`integer(0, # lower\\n  10)`) would be swallowed by
      the patch, so it no-ops instead.

  The call is anchored at the diagnostic's line *and* column, so a same-named
  `integer/2` defined or called elsewhere in the file is never touched. The
  qualified `StreamData.integer(1, 10)` spelling compiles (it only warns) and
  is out of scope. The `should_report?/2` phase hook keeps `analyze` honest by
  reporting an issue only when `fix/2` would actually rewrite the source.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @message_prefix "undefined function integer/2"

  # Claimed ahead of the generic `UndefinedFunction` rule (priority 500), which
  # matches the same message but has no repair for `integer/2`.
  @impl true
  def priority, do: 400

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    msg == @message_prefix or String.starts_with?(msg, @message_prefix <> " ")
  end

  def match?(_), do: false

  @doc """
  Phase hook (`Credence.Semantic.match_rules/2`): report an issue only when
  `fix/2` would actually rewrite the source. The same message is emitted for
  every undefined local `integer/2`, most of which this rule leaves alone.
  """
  def should_report?(diagnostic, source), do: fix(source, diagnostic) != source

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_stream_data_integer_two_args,
      message: "StreamData has no integer/2 — the bounded generator is integer(min..max)",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    with {line_no, col} when is_integer(line_no) <- position(diagnostic),
         {:ok, ast} <- Sourceror.parse_string(source),
         true <- imports_stream_data?(ast, line_no),
         {:ok, arg1, arg2} <- flagged_call(ast, {line_no, col}),
         {:ok, range} <- comma_range(source, arg1, arg2) do
      Sourceror.patch_string(source, [%{range: range, change: ".."}])
    else
      _ -> source
    end
  end

  # Is an `import StreamData` (with or without options) — or a
  # `use ExUnitProperties`, which imports StreamData for property tests — in
  # lexical scope at `line_no`? An import earlier in the file counts only when
  # every `defmodule` wrapping it also wraps the flagged call, so a sibling
  # module that never imported StreamData is left alone.
  defp imports_stream_data?(ast, line_no) do
    modules = module_ranges(ast)
    target = wrapping_modules(modules, line_no)

    Enum.any?(import_lines(ast), fn line ->
      line < line_no and MapSet.subset?(wrapping_modules(modules, line), target)
    end)
  end

  defp import_lines(ast) do
    {_, lines} =
      Macro.prewalk(ast, [], fn
        {:import, meta, [{:__aliases__, _, [:StreamData]} | _]} = node, acc ->
          {node, [meta[:line] | acc]}

        {:use, meta, [{:__aliases__, _, [:ExUnitProperties]} | _]} = node, acc ->
          {node, [meta[:line] | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.filter(lines, &is_integer/1)
  end

  defp module_ranges(ast) do
    {_, ranges} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _, _} = node, acc ->
          case Sourceror.get_range(node) do
            %{start: [line: start_line, column: _], end: [line: end_line, column: _]} ->
              {node, [{start_line, end_line} | acc]}

            _ ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    ranges
  end

  defp wrapping_modules(modules, line) do
    for {start_line, end_line} <- modules,
        line >= start_line,
        line <= end_line,
        into: MapSet.new(),
        do: {start_line, end_line}
  end

  # The flagged call is the two-argument `integer` call whose own token starts
  # at the diagnostic's line/column. Without a column, a lone candidate on the
  # flagged line is unambiguous; anything else no-ops rather than guess.
  defp flagged_call(ast, {line_no, col}) do
    {_, found} =
      Macro.prewalk(ast, [], fn
        {:integer, meta, [arg1, arg2]} = node, acc ->
          if meta[:line] == line_no and (col == nil or meta[:column] == col) and
               safe_arg?(arg1) and safe_arg?(arg2) do
            {node, [{arg1, arg2} | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    case found do
      [{arg1, arg2}] -> {:ok, arg1, arg2}
      _ -> :error
    end
  end

  # An argument `..` can never re-associate: an integer literal, a negated
  # integer literal, or a bare variable. Sourceror wraps literals in
  # `:__block__` nodes; a variable carries an atom (or nil) context, which
  # every wrapped literal and alias fails.
  defp safe_arg?({:__block__, _, [value]}) when is_integer(value), do: true
  defp safe_arg?({:-, _, [{:__block__, _, [value]}]}) when is_integer(value), do: true
  defp safe_arg?({name, _, context}) when is_atom(name) and is_atom(context), do: true
  defp safe_arg?(_), do: false

  # The span between the two arguments, which must hold nothing but the comma
  # and whitespace — a comment there would be destroyed by the patch.
  defp comma_range(source, arg1, arg2) do
    with %{end: [line: l1, column: c1]} <- Sourceror.get_range(arg1),
         %{start: [line: l2, column: c2]} <- Sourceror.get_range(arg2),
         text when is_binary(text) <- slice(source, {l1, c1}, {l2, c2}),
         true <- Regex.match?(~r/\A,\s*\z/, text) do
      {:ok, %{start: [line: l1, column: c1], end: [line: l2, column: c2]}}
    else
      _ -> :error
    end
  end

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
