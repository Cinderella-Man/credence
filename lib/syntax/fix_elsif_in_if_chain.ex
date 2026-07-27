defmodule Credence.Syntax.FixElsifInIfChain do
  @moduledoc """
  Detects and rewrites Ruby/Python-style `if`/`elsif`/`else` chains to idiomatic `cond`.

  LLMs translating from Ruby (`elsif`) or Python (`elif`) emit that keyword
  inside `if` blocks, which is not valid Elixir syntax. Both spellings are
  handled — for a long time this rule advertised `elif` in its documentation
  while both its regexes matched `elsif` only, so the Python spelling parsed
  as a call to an undefined `elif/2` and was never repaired at all.
  The parser misinterprets the
  code, often emitting misleading errors like "cannot invoke defp/2 inside
  function/macro" rather than a clear parse failure. Converting these chains to
  `cond` is behaviour-preserving and idiomatic.

  ## Bad (won't parse)

      if data.valid_from && DateTime.compare(now, data.valid_from) == :lt do
        {:error, :not_yet_valid}
      elsif data.valid_until && DateTime.compare(now, data.valid_until) == :gt do
        {:error, :expired}
      else
        :ok
      end

  ## Good

      cond do
        data.valid_from && DateTime.compare(now, data.valid_from) == :lt ->
          {:error, :not_yet_valid}
        data.valid_until && DateTime.compare(now, data.valid_until) == :gt ->
          {:error, :expired}
        true ->
          :ok
      end

  ## What it refuses to touch

  The rewrite is line-based: each branch condition is lifted off its `if`/`elsif`
  header and each branch body is re-indented under a `cond` clause. That is only
  meaning-preserving when the whole chain can be read off cleanly, so the fix
  bails out (leaving the source exactly as it found it) on:

    * a condition that is not `if <expr> do` / `elsif <expr> do` on one line
      (multi-line conditions, `elsif x, do: y` one-liners, a trailing comment
      after `do`) — guessing a condition would silently change which branch runs;
    * a chain with no `else`/`end` at the header's own indentation — without a
      terminator the rewrite would swallow whatever follows;
    * a branch body holding a multi-line string literal (a heredoc, or a `"`
      string spanning lines), whose *value* would change when the body is
      re-indented.

  `analyze/1` reports exactly what `fix/1` will rewrite — the shapes above are
  left unflagged rather than reported as a problem the fix refuses to solve.
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  @elsif_re ~r/^\s*els?if\b/
  @if_do_re ~r/^\s*if\s+.+?\s+do\s*$/
  # A branch boundary only has to *start* with `else`; `find_else_at_indent/3`
  # then insists on a bare `else`, so `else # note` stops the scan and bails
  # instead of being swallowed into the previous branch's body.
  @else_start_re ~r/^\s*else\b/
  @else_re ~r/^\s*else\s*$/
  @end_re ~r/^\s*end\s*$/

  @impl true
  def analyze(source) do
    lines = String.split(source, "\n")

    with {:ok, idx} <- find_elsif(lines),
         rewritten when rewritten != lines <- rewrite_block(lines, idx) do
      [
        %Issue{
          rule: :fix_elsif_in_if_chain,
          message: "Use `cond` instead of `elsif`/`elif` inside `if`",
          meta: %{line: idx + 1}
        }
      ]
    else
      _ -> []
    end
  end

  @impl true
  def fix(source) do
    lines = String.split(source, "\n")

    case find_elsif(lines) do
      {:ok, idx} ->
        lines |> rewrite_block(idx) |> Enum.join("\n")

      :not_found ->
        source
    end
  end

  # An `elsif` inside a heredoc is documentation (this module's own `@moduledoc`
  # is an example), not code: rewriting it would change a string's value. Track
  # the heredoc delimiters seen so far and only take an `elsif` found outside one.
  defp find_elsif(lines) do
    lines
    |> Enum.with_index()
    |> Enum.reduce_while({:not_found, false}, fn {line, idx}, {_acc, in_heredoc?} ->
      if not in_heredoc? and Regex.match?(@elsif_re, line) do
        {:halt, {{:ok, idx}, in_heredoc?}}
      else
        {:cont, {:not_found, toggle_heredoc(in_heredoc?, line)}}
      end
    end)
    |> elem(0)
  end

  defp toggle_heredoc(in_heredoc?, line) do
    delimiters = count(line, ~s(""")) + count(line, "'''")
    if rem(delimiters, 2) == 1, do: not in_heredoc?, else: in_heredoc?
  end

  defp count(line, needle), do: length(String.split(line, needle)) - 1

  defp rewrite_block(lines, elsif_idx) do
    elsif_indent = get_indent(Enum.at(lines, elsif_idx))

    with {:ok, if_idx} <- scan_back_for_if(lines, elsif_idx - 1, elsif_indent),
         {:ok, branches, end_idx, else_branches} <-
           collect_branches(lines, if_idx, elsif_idx, elsif_indent),
         :ok <- reindentable(branches ++ else_branches) do
      cond_lines = build_cond(branches, else_branches, get_indent(Enum.at(lines, if_idx)))
      Enum.take(lines, if_idx) ++ cond_lines ++ Enum.drop(lines, end_idx + 1)
    else
      # `:not_found` (no matching `if`), `:bail` (a condition or the chain's
      # terminator could not be read off cleanly) or `:unsafe` (a body holds a
      # multi-line string literal). Emitting a guessed clause there would
      # silently change behaviour, so leave the source untouched — `analyze/1`
      # asks the same question, so nothing gets flagged that this refuses.
      _ -> lines
    end
  end

  defp scan_back_for_if(lines, idx, target_indent) when idx >= 0 do
    line = Enum.at(lines, idx)

    cond do
      Regex.match?(@if_do_re, line) and get_indent(line) == target_indent ->
        {:ok, idx}

      get_indent(line) < target_indent ->
        :not_found

      true ->
        scan_back_for_if(lines, idx - 1, target_indent)
    end
  end

  defp scan_back_for_if(_, _, _), do: :not_found

  defp collect_branches(lines, if_idx, elsif_idx, elsif_indent) do
    if_body = slice(lines, if_idx + 1, elsif_idx - 1)

    with {:ok, if_cond} <- extract_condition(Enum.at(lines, if_idx)),
         {:ok, branches, rest_idx} <-
           collect_elsif_branches(lines, elsif_idx, elsif_indent, [{if_cond, if_body}]) do
      case find_else_at_indent(lines, rest_idx, elsif_indent) do
        {:ok, else_idx, end_idx} ->
          {:ok, branches, end_idx, [{"true", slice(lines, else_idx + 1, end_idx - 1)}]}

        {:no_else, end_idx} ->
          # No trailing `else`: an `if` without an `else` evaluates to `nil`
          # when no branch matches, but `cond` raises `CondClauseError`. Add an
          # explicit `true -> nil` clause so the rewrite keeps the `nil` answer.
          {:ok, branches, end_idx, [{"true", ["nil"]}]}

        :bail ->
          :bail
      end
    end
  end

  defp collect_elsif_branches(lines, idx, target_indent, acc) do
    line = Enum.at(lines, idx)

    if line != nil and Regex.match?(@elsif_re, line) and get_indent(line) == target_indent do
      with {:ok, cond_str} <- extract_condition_from_elsif(line),
           {:ok, next_idx} <- find_branch_boundary(lines, idx + 1, target_indent) do
        body = slice(lines, idx + 1, next_idx - 1)
        collect_elsif_branches(lines, next_idx, target_indent, acc ++ [{cond_str, body}])
      else
        _ -> :bail
      end
    else
      {:ok, acc, idx}
    end
  end

  defp find_branch_boundary(lines, idx, target_indent) do
    find_line(lines, idx, fn line ->
      get_indent(line) == target_indent and
        (Regex.match?(@elsif_re, line) or Regex.match?(@else_start_re, line) or
           Regex.match?(@end_re, line))
    end)
  end

  defp find_else_at_indent(lines, idx, target_indent) do
    line = Enum.at(lines, idx)

    cond do
      line == nil or get_indent(line) != target_indent ->
        :bail

      Regex.match?(@else_re, line) ->
        case find_end(lines, idx + 1, target_indent) do
          {:ok, end_idx} -> {:ok, idx, end_idx}
          :bail -> :bail
        end

      Regex.match?(@end_re, line) ->
        {:no_else, idx}

      true ->
        :bail
    end
  end

  defp find_end(lines, idx, target_indent) do
    find_line(lines, idx, fn line ->
      get_indent(line) == target_indent and Regex.match?(@end_re, line)
    end)
  end

  defp find_line(lines, idx, fun) do
    case Enum.find(idx..(length(lines) - 1)//1, fn i -> fun.(Enum.at(lines, i)) end) do
      nil -> :bail
      i -> {:ok, i}
    end
  end

  # Every body line is re-indented under its `cond` clause. That is only safe for
  # lines whose leading whitespace is insignificant — inside a multi-line string
  # literal it is part of the value, so refuse those chains outright.
  defp reindentable(branches) do
    unsafe? =
      Enum.any?(branches, fn {_cond, body} -> Enum.any?(body, &multiline_string_risk?/1) end)

    if unsafe?, do: :unsafe, else: :ok
  end

  defp multiline_string_risk?(line) do
    String.contains?(line, ~s(""")) or String.contains?(line, "'''") or odd_quotes?(line)
  end

  defp odd_quotes?(line) do
    line
    |> String.replace(~r/\\./, "")
    |> String.replace(~r/\?"/, "")
    |> String.graphemes()
    |> Enum.count(&(&1 == "\""))
    |> rem(2) == 1
  end

  defp build_cond(branches, else_branches, base_indent) do
    all_branches = branches ++ else_branches
    branch_indent = base_indent <> "  "
    body_indent = branch_indent <> "  "

    branch_lines =
      Enum.flat_map(all_branches, fn {cond_str, body_lines} ->
        clean_body = Enum.reject(body_lines, &blank?/1)
        expr_lines = Enum.reject(clean_body, &comment?/1)

        case {clean_body, expr_lines} do
          # An empty branch body evaluates to `nil` in `if`; a bodyless `cond`
          # clause does not even parse, so spell the `nil` out.
          {[], _} ->
            ["#{branch_indent}#{cond_str} -> nil"]

          {[single], [_]} ->
            ["#{branch_indent}#{cond_str} -> #{String.trim(single)}"]

          {body, []} ->
            # Comments only — same story as an empty body, with the comments kept
            # (in their original order) above the `nil`.
            ["#{branch_indent}#{cond_str} ->"] ++
              Enum.map(body, &"#{body_indent}#{String.trim(&1)}") ++ ["#{body_indent}nil"]

          {body, _} ->
            ["#{branch_indent}#{cond_str} ->"] ++
              Enum.map(body, &"#{body_indent}#{String.trim(&1)}")
        end
      end)

    ["#{base_indent}cond do"] ++ branch_lines ++ ["#{base_indent}end"]
  end

  defp get_indent(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, indent] -> indent
      _ -> ""
    end
  end

  defp extract_condition(line) do
    case Regex.run(~r/^\s*if\s+(.+?)\s+do\s*$/, line) do
      [_, cond] -> {:ok, cond}
      _ -> :bail
    end
  end

  defp extract_condition_from_elsif(line) do
    case Regex.run(~r/^\s*els?if\s+(.+?)\s+do\s*$/, line) do
      [_, cond] -> {:ok, cond}
      _ -> :bail
    end
  end

  defp slice(_lines, lo, hi) when hi < lo, do: []
  defp slice(lines, lo, hi), do: Enum.slice(lines, lo..hi//1)

  defp blank?(line), do: String.trim(line) == ""
  defp comment?(line), do: Regex.match?(~r/^\s*#/, line)
end
