defmodule Credence.Rule.NoTakeWhileLengthCheck do
  @moduledoc """
  Detects `Enum.take_while/2` piped into `length/1` or `Enum.count/1`,
  which materializes an intermediate list only to count it.

  ## Why this matters

  LLMs generate this pattern when they think procedurally: "keep going
  while the condition holds, then check how far I got."  The idiomatic
  Elixir approach depends on intent:

      # Flagged — materializes a list just to count it
      0..(half - 1)
      |> Enum.take_while(fn i ->
        Enum.at(graphemes, start + i) == Enum.at(graphemes, start + len - 1 - i)
      end)
      |> length() == half

      # If checking "did all pass?" → use Enum.all?/2
      Enum.all?(0..(half - 1), fn i -> ... end)

      # If counting consecutive matches → use Enum.reduce_while/3
      Enum.reduce_while(range, 0, fn i, count ->
        if condition, do: {:cont, count + 1}, else: {:halt, count}
      end)

  `Enum.take_while |> length` always allocates a throwaway list.
  `Enum.all?` and `Enum.reduce_while` do not.

  ## Flagged patterns

  - `Enum.take_while(enum, fun) |> length()`
  - `Enum.take_while(enum, fun) |> Enum.count()`
  - `length(Enum.take_while(enum, fun))`
  - `Enum.count(Enum.take_while(enum, fun))`
  - `enum |> Enum.take_while(fun) |> length()`
  """

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case check_node(node) do
          {:ok, issue} -> {node, [issue | issues]}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    ast = Sourceror.parse_string!(source)
    patches = collect_fixes(ast, source)

    patches
    |> Enum.sort_by(fn {start, _, _} -> start end, :desc)
    |> Enum.reduce(source, fn {start_off, end_off, replacement}, src ->
      before = binary_part(src, 0, start_off)
      after_ = binary_part(src, end_off, byte_size(src) - end_off)
      before <> replacement <> after_
    end)
  end

  # Single-pass collection: handles both pipeline and direct call patterns.
  # Returns early (without visiting children) when a pattern matches,
  # preventing overlapping patches from inner take_while nodes.
  defp collect_fixes(ast, source) do
    {_, patches} =
      Macro.prewalk(ast, [], fn
        # Pipeline: ... |> Enum.take_while(fun) |> length()
        {:|>, _, _} = node, acc ->
          steps = flatten_pipeline(node)

          case find_pipeline_take_while_pairs(steps) do
            [] ->
              {node, acc}

            pairs ->
              new_patches =
                Enum.map(pairs, fn {tw_idx, count_idx} ->
                  build_pipeline_patch(
                    Enum.at(steps, tw_idx),
                    Enum.at(steps, count_idx),
                    source
                  )
                end)

              {node, new_patches ++ acc}
          end

        # Direct call: length(Enum.take_while(enum, fun))
        {:length, _, [arg]} = node, acc ->
          if take_while_call?(arg) do
            {node, [build_direct_patch(node, arg, source) | acc]}
          else
            {node, acc}
          end

        # Direct call: Enum.count(Enum.take_while(enum, fun))
        {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, [arg]} = node, acc ->
          if take_while_call?(arg) do
            {node, [build_direct_patch(node, arg, source) | acc]}
          else
            {node, acc}
          end

        # Standalone take_while: skip (it's inside a wrapper that was already patched)
        {{:., _, [{:__aliases__, _, [:Enum]}, :take_while]}, _, _} = node, acc ->
          {node, acc}

        node, acc ->
          {node, acc}
      end)

    patches
  end

  # --- Pipeline patches ---

  defp build_pipeline_patch(tw_step, count_step, source) do
    tw_range = Sourceror.get_range(tw_step, include_parens: true)
    count_range = Sourceror.get_range(count_step, include_parens: true)

    start_off = byte_offset(tw_range.start, source)
    end_off = byte_offset(count_range.end, source)

    fun_text = take_while_fun_text(tw_step)
    enum_text = take_while_enum_text(tw_step)
    replacement = build_reduce_while_text("Enum", fun_text, enum_text)

    {start_off, end_off, replacement}
  end

  defp find_pipeline_take_while_pairs(steps) do
    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.reduce([], fn {[first, second], idx}, acc ->
      if take_while_step?(first) and counting_step?(second),
        do: [{idx, idx + 1} | acc],
        else: acc
    end)
    |> Enum.reverse()
  end

  # --- Direct call patches ---

  defp build_direct_patch(outer_node, take_while_node, source) do
    outer_range = Sourceror.get_range(outer_node, include_parens: true)

    start_off = byte_offset(outer_range.start, source)
    end_off = byte_offset(outer_range.end, source)

    fun_text = take_while_fun_text(take_while_node)
    enum_text = take_while_enum_text(take_while_node)
    replacement = build_reduce_while_text("Enum", fun_text, enum_text)

    {start_off, end_off, replacement}
  end

  # --- Source-level helpers ---

  defp take_while_fun_text({{:., _, [{:__aliases__, _, [:Enum]}, :take_while]}, _, [_enum, fun]}) do
    Sourceror.to_string(fun)
  end

  defp take_while_fun_text({{:., _, [{:__aliases__, _, [:Enum]}, :take_while]}, _, [fun]}) do
    Sourceror.to_string(fun)
  end

  defp take_while_enum_text({{:., _, [{:__aliases__, _, [:Enum]}, :take_while]}, _, [enum, _fun]}) do
    Sourceror.to_string(enum)
  end

  defp take_while_enum_text({{:., _, [{:__aliases__, _, [:Enum]}, :take_while]}, _, [_fun]}) do
    nil
  end

  # Sourceror positions are 1-indexed for both line and column.
  # byte_offset converts to absolute byte position in the source string.
  defp byte_offset(%{line: line, column: col}, source) do
    lines = String.split(source, "\n")

    line_offset =
      lines
      |> Enum.take(line - 1)
      |> Enum.map(&(byte_size(&1) + 1))
      |> Enum.sum()

    line_offset + col - 1
  end

  defp byte_offset([line: line, column: col], source) do
    byte_offset(%{line: line, column: col}, source)
  end

  defp build_reduce_while_text(enum_mod, fun_text, nil) do
    "#{enum_mod}.reduce_while(0, fn elem, acc -> if #{fun_text}.(elem), do: {:cont, acc + 1}, else: {:halt, acc} end)"
  end

  defp build_reduce_while_text(enum_mod, fun_text, enum_text) do
    "#{enum_mod}.reduce_while(#{enum_text}, 0, fn elem, acc -> if #{fun_text}.(elem), do: {:cont, acc + 1}, else: {:halt, acc} end)"
  end

  # --- AST pattern helpers (shared by check and fix) ---

  defp check_node({:|>, meta, _} = node) do
    pipeline = flatten_pipeline(node)
    check_pipeline(pipeline, meta)
  end

  defp check_node({:length, meta, [inner]}) do
    if take_while_call?(inner), do: {:ok, build_issue(meta)}, else: :error
  end

  defp check_node({{:., meta, [mod, :count]}, _, [inner]}) do
    if enum_module?(mod) and take_while_call?(inner), do: {:ok, build_issue(meta)}, else: :error
  end

  defp check_node(_), do: :error

  defp check_pipeline(steps, meta) do
    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn [first, second] ->
      take_while_step?(first) and counting_step?(second)
    end)
    |> then(fn
      true -> {:ok, build_issue(meta)}
      false -> :error
    end)
  end

  defp take_while_call?({{:., _, [mod, :take_while]}, _, args})
       when is_list(args) and length(args) == 2,
       do: enum_module?(mod)

  defp take_while_call?(_), do: false

  defp take_while_step?({{:., _, [mod, :take_while]}, _, args})
       when is_list(args),
       do: enum_module?(mod)

  defp take_while_step?(_), do: false

  defp counting_step?({:length, _, []}), do: true

  defp counting_step?({{:., _, [mod, :count]}, _, []}),
    do: enum_module?(mod)

  defp counting_step?(_), do: false

  defp flatten_pipeline({:|>, _, [left, right]}), do: flatten_pipeline(left) ++ [right]
  defp flatten_pipeline(expr), do: [expr]

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :no_take_while_length_check,
      message: build_message(),
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp build_message do
    """
    `Enum.take_while/2` piped into `length/1` allocates an intermediate \
    list just to count it.
    If checking whether all elements pass the condition:
        Enum.all?(enumerable, predicate)
    If counting consecutive matches from the start:
        Enum.reduce_while(enumerable, 0, fn elem, count ->
          if condition, do: {:cont, count + 1}, else: {:halt, count}
        end)
    """
  end
end
