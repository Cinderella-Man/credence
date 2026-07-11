defmodule Credence.Semantic.NoCaptureAsBitwiseAnd do
  @moduledoc """
  Repairs the common Python→Elixir translation error where `&` is written as
  the bitwise-AND operator.

  In Python (and C) `x & 1` means bitwise AND. In Elixir `&` is the *capture*
  operator, so `x & 1` parses as `x(&1)` — a call passing capture argument
  `&1` outside any `&(...)`. The compiler rejects it with an `:error`-severity
  diagnostic:

      capture argument &1 must be used within the capture operator &

  whose `{line, column}` points straight at the `&`.

  The code never compiles for any input, so this is a REPAIR: the fix rewrites
  the offending `IDENT & <integer>` to the idiomatic, fully-qualified
  `Bitwise.band(IDENT, <integer>)` (no `import` needed). It is targeted by the
  diagnostic column, so only that one operator changes — never a legitimate
  capture elsewhere on the line (`&foo/1`, `&(&1 + 1)`).
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  # `IDENT & <integer literal>` — the exact shape that yields the
  # "capture argument &N" diagnostic. Used for the bare-line fallback when no
  # column is available.
  @band_regex ~r/([A-Za-z_]\w*)\s*&\s*(\d+)/

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, "capture argument") and
      String.contains?(msg, "must be used within the capture operator")
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :no_capture_as_bitwise_and,
      message: msg,
      meta: %{line: extract_line(position)}
    }
  end

  @impl true
  def fix(source, %{position: {line, col}}) when is_integer(line) and is_integer(col) do
    fixed = fix_at_column(source, line, col)
    if fixed != source, do: fixed, else: fix_pipe_capture(source)
  end

  def fix(source, %{position: line}) when is_integer(line) do
    fixed = update_line(source, line, fn text -> rewrite_first(text) || text end)
    if fixed != source, do: fixed, else: fix_pipe_capture(source)
  end

  def fix(source, _diagnostic), do: source

  defp extract_line({line, _col}) when is_integer(line), do: line
  defp extract_line(line) when is_integer(line), do: line
  defp extract_line(_), do: nil

  defp fix_at_column(source, line_no, col) do
    update_line(source, line_no, fn text ->
      with true <- col >= 1 and col <= String.length(text),
           {before, "&" <> _ = at} <- String.split_at(text, col - 1),
           rewritten when is_binary(rewritten) <- rewrite_split(before, at) do
        rewritten
      else
        _ -> rewrite_first(text) || text
      end
    end)
  end

  # `before` ends with the left operand, `at` begins with `& <digits>`.
  # Rewrite just `LHS & DIGITS` → `Bitwise.band(LHS, DIGITS)`, keeping the
  # surrounding text on the line intact.
  defp rewrite_split(before, at) do
    with [lhs_with_ws] <- Regex.run(~r/[A-Za-z_]\w*\s*$/, before),
         [amp_with_digits] <- Regex.run(~r/^&\s*\d+/, at) do
      lhs = String.trim_trailing(lhs_with_ws)
      digits = amp_with_digits |> String.trim_leading("&") |> String.trim()
      prefix = binary_part(before, 0, byte_size(before) - byte_size(lhs_with_ws))

      rest =
        binary_part(at, byte_size(amp_with_digits), byte_size(at) - byte_size(amp_with_digits))

      prefix <> "Bitwise.band(" <> lhs <> ", " <> digits <> ")" <> rest
    else
      _ -> nil
    end
  end

  # Rewrite the first `IDENT & DIGITS` on a line; nil when the line has none.
  defp rewrite_first(text) do
    if Regex.match?(@band_regex, text) do
      Regex.replace(@band_regex, text, "Bitwise.band(\\1, \\2)", global: false)
    end
  end

  # AST-based fix for bare &N in pipe steps. Wraps the pipe step in
  # then(fn wqN -> ... end) and replaces all bare &N with the bound variable.
  defp fix_pipe_capture(source) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, counter} = transform_pipes(ast, 0)
      if counter > 0, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  defp transform_pipes(ast, counter) do
    Macro.prewalk(ast, counter, fn
      {:|>, pipe_meta, [left, right]}, cnt ->
        if has_bare_capture?(right) do
          var_name = :"wq#{cnt + 1}"
          new_right = add_head_and_replace(right, var_name)
          then_call = build_then_call(var_name, new_right)
          {{:|>, pipe_meta, [left, then_call]}, cnt + 1}
        else
          {{:|>, pipe_meta, [left, right]}, cnt}
        end

      node, cnt ->
        {node, cnt}
    end)
  end

  defp has_bare_capture?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:&, _, [n]} = node, _acc when is_integer(n) -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  defp replace_bare_captures(ast, var_name) do
    Macro.prewalk(ast, fn
      {:&, meta, [n]} when is_integer(n) -> {var_name, meta, nil}
      node -> node
    end)
  end

  # Replace bare &N with var_name AND add var_name as the first argument
  # (the head, which in a pipe comes from the piped value).
  defp add_head_and_replace(ast, var_name) do
    var_ast = {var_name, [], nil}
    replaced = replace_bare_captures(ast, var_name)

    case replaced do
      # Remote function call: {{:., meta, [mod, func]}, call_meta, args}
      {{:., meta, [mod, func]}, call_meta, args} when is_list(args) ->
        {{:., meta, [mod, func]}, call_meta, [var_ast | args]}

      # Local function call: {func_name, meta, args}
      {func_name, meta, args} when is_atom(func_name) and is_list(args) ->
        {func_name, meta, [var_ast | args]}

      # Other — return as-is
      _ ->
        replaced
    end
  end

  defp build_then_call(var_name, body) do
    var_ast = {var_name, [], nil}
    {:then, [], [{:fn, [], [{:->, [], [[var_ast], body]}]}]}
  end

  defp update_line(source, line_no, fun) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn
      {text, ^line_no} -> fun.(text)
      {text, _} -> text
    end)
  end
end
