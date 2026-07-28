defmodule Credence.Syntax.NoPythonMultiReturn do
  @moduledoc """
  Fixes Python-style bare comma multi-return expressions.

  LLMs translating Python's `return a, b` produce `a, b` at the top level of
  an Elixir function body. A bare comma at nesting depth 0 is a syntax error
  in Elixir — the parser reports "syntax error before: ','".

  The fix deterministically wraps the comma-separated expressions in a tuple:
  `a, b` becomes `{a, b}`.

  ## Bad (won't parse)

      {:ok, new_state}, [event]

  ## Good

      {{:ok, new_state}, [event]}

  ## Why so narrow

  The phase runs every rule's `fix/1` over the whole file whenever the file
  fails to parse, and the parse error is usually on some *other* line. So this
  rule must be a no-op on every valid line it walks past, and it works on raw
  text with no AST to lean on. Three things enforce that:

    * **Literals are not code.** `compute_line_starts/1` tracks comments,
      quoted strings and heredocs, so a doc's prose (`Returns a, b.`) and a
      comment are never candidates no matter what punctuation they contain.

    * **Each candidate is parser-checked in isolation** — the line as written
      must *fail* to parse and the wrapped line must *succeed*. Any line that
      is a valid fragment of a larger construct is rejected by the first half.

    * **The line must be self-contained.** A leading or trailing depth-zero
      comma means the expression continues on an adjacent line. Elixir accepts
      a trailing comma inside a tuple (`{1, 2,}` parses as `{1, 2}`), so the
      parse check alone would wave those through.

  Together these hold the rule to zero rewrites across the ~29k valid Elixir
  files in this repo and its corpus, while still repairing the shape above.
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  @impl true
  def analyze(source) do
    source
    |> find_bare_comma_lines()
    |> Enum.map(fn line_no ->
      %Issue{
        rule: :no_python_multi_return,
        message:
          "Bare comma multi-return is not valid Elixir. " <>
            "Wrap expressions in a tuple `{a, b}` instead.",
        meta: %{line: line_no}
      }
    end)
  end

  @impl true
  def fix(source) do
    flagged = MapSet.new(find_bare_comma_lines(source))

    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {line, line_no} ->
      if MapSet.member?(flagged, line_no) do
        fix_line(line)
      else
        line
      end
    end)
  end

  # Walk the entire source to find lines that have bare commas at global
  # depth 0.  This avoids the false-positive where a comma inside a
  # multi-line `%{}`, `[]`, or `()` is treated as depth-0 because each
  # line was previously analysed in isolation.
  defp find_bare_comma_lines(source) do
    line_starts = compute_line_starts(source)
    lines = String.split(source, "\n")
    clause_lines = for_with_clause_continuation_lines(lines)
    defstruct_lines = defstruct_bare_atom_lines(lines, line_starts)

    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      {start_depth, in_literal?} = Map.get(line_starts, line_no, {0, false})

      if start_depth == 0 and
           not in_literal? and
           not comment_line?(line) and
           not has_left_arrow_at_depth_zero?(line) and
           not has_struct_pipe_at_depth_zero?(line) and
           not wrapped_clause_head?(lines, line_no) and
           not MapSet.member?(clause_lines, line_no) and
           not MapSet.member?(defstruct_lines, line_no) and
           match?({:ok, _}, wrapped_line(line)) do
        [line_no]
      else
        []
      end
    end)
  end

  # True when the line is the head of a `case`/`fn`/`catch` clause whose `->`
  # wrapped onto a following line. The same-line `arrow_ahead?/1` lookahead
  # cannot see it, so the comma separating the clause's patterns looks like a
  # bare multi-return:
  #
  #     catch
  #       :exit, value
  #       when value == :normal
  #       when tuple_size(value) == 2 and elem(value, 0) == :shutdown ->
  #         :erlang.raise(:exit, value, __STACKTRACE__)
  #
  # So the scan walks forward over following non-blank lines for as long as they
  # continue the head — a `when` guard, or the arrow itself — and reports a
  # clause head as soon as one of them carries the `->`.
  defp wrapped_clause_head?(lines, line_no) do
    lines
    |> Enum.drop(line_no)
    |> Enum.reject(fn l -> String.trim(l) == "" end)
    |> Enum.reduce_while(false, fn l, _ ->
      trimmed = String.trim_leading(l)

      cond do
        has_arrow_at_depth_zero?(l) and continues_clause_head?(trimmed) -> {:halt, true}
        starts_with_when?(trimmed) -> {:cont, false}
        true -> {:halt, false}
      end
    end)
  end

  defp continues_clause_head?(trimmed) do
    starts_with_when?(trimmed) or String.starts_with?(trimmed, "->")
  end

  defp starts_with_when?(trimmed) do
    case trimmed do
      "when" -> true
      "when " <> _ -> true
      "when\t" <> _ -> true
      _ -> false
    end
  end

  defp has_arrow_at_depth_zero?(line), do: arrow_ahead?(String.to_charlist(line))

  # The safe core. `analyze` and `fix` both route through this, so they can
  # never disagree: a line is only ever reported when there is a wrap to apply,
  # and the wrap is only ever applied when the line is provably a bare
  # multi-return *in isolation*.
  #
  # Two parser-checked conditions, on the line by itself:
  #
  #   1. the line as written does **not** parse — so it cannot be a valid line
  #      of a larger construct that the depth walker mis-tracked (a heredoc's
  #      prose, a continuation inside a multi-line list, a paren-less call);
  #   2. the same line wrapped in `{…}` **does** parse.
  #
  # Together these mean the rewrite turns a locally-broken line into a
  # locally-valid tuple, which is exactly the Python `return a, b` shape. Any
  # line that fails either check is left alone, even if every heuristic above
  # thought it looked like a bare comma.
  #
  # The line must also be self-contained: no leading or trailing comma, and no
  # blank segment. A comma at either end means the expression continues on an
  # adjacent line, and Elixir accepts a trailing comma inside a tuple
  # (`{1, 2,}` parses as `{1, 2}`), so the parse test above cannot catch it.
  # The last line of a multi-line `when` guard is the mainstream case:
  #
  #     defp same?({n, _, c1}, {n, _, c2})
  #          when is_atom(n) and (is_nil(c1) or is_atom(c1)) and
  #                 (is_nil(c2) or is_atom(c2)),
  #          do: true
  #
  # as is a wrapped list of literals:
  #
  #     [?-, c(c1), c(c2), c(c3), c(c4),
  #      ?-, c(d1), c(d2)]
  defp wrapped_line(line) do
    parts = split_at_depth_zero_commas(line)
    trimmed = String.trim(line)

    with [_, _ | _] <- parts,
         false <- String.starts_with?(trimmed, ","),
         false <- String.ends_with?(trimmed, ","),
         true <- Enum.all?(parts, &(String.trim(to_string(&1)) != "")),
         joined = Enum.join(parts, ","),
         {leading, rest} = split_leading_ws(joined),
         fixed = leading <> "{" <> rest <> "}",
         false <- parses?(line),
         true <- parses?(fixed) do
      {:ok, fixed}
    else
      _ -> :error
    end
  end

  defp parses?(line) do
    match?({:ok, _}, Code.string_to_quoted(String.trim(line)))
  end

  # Returns a MapSet of line numbers that are bare atoms inside a bare-form
  # `defstruct` declaration (no bracket).  These lines look like bare commas
  # at depth 0 but are actually struct field definitions.
  #
  # Example:
  #
  #     defstruct :field_a,
  #               :field_b,     ← bare comma, but a defstruct field separator
  #               :field_c
  #
  # This also covers the single-line case `defstruct :a, :b, :c` where the
  # entire line is marked.
  defp defstruct_bare_atom_lines(lines, line_starts) do
    lines
    |> Enum.with_index(1)
    |> Enum.reduce({false, MapSet.new()}, fn {line, line_no}, {in_defstruct, acc} ->
      {start_depth, _in_literal?} = Map.get(line_starts, line_no, {0, false})
      trimmed = String.trim_leading(line)
      trailing = String.trim_trailing(trimmed)
      has_trailing_comma = String.ends_with?(trailing, ",")

      cond do
        # Enter bare-atom defstruct: starts with `defstruct`, has bare atom
        # args, no bracket form
        not in_defstruct and start_depth == 0 and defstruct_bare_atom_start?(trimmed) ->
          {true, MapSet.put(acc, line_no)}

        # Inside defstruct, depth 0, bare atom continuation
        in_defstruct and start_depth == 0 and bare_atom_only?(trimmed) ->
          # Mark for exclusion; stay in context if trailing comma (more fields)
          {has_trailing_comma, MapSet.put(acc, line_no)}

        # Inside defstruct, depth 0, non-bare-atom (keyword entry, etc.)
        # Stay in context if trailing comma; exit otherwise
        in_defstruct and start_depth == 0 ->
          {has_trailing_comma, acc}

        # Inside defstruct, depth > 0 (multiline default value)
        in_defstruct ->
          {true, acc}

        true ->
          {false, acc}
      end
    end)
    |> elem(1)
  end

  # Returns true when `trimmed` starts with `defstruct` followed by bare atom
  # arguments (no bracket).  This detects the bare-form defstruct pattern:
  # `defstruct :field_a, :field_b, :field_c`
  defp defstruct_bare_atom_start?(trimmed) do
    case trimmed do
      "defstruct " <> rest ->
        rest_trimmed = String.trim_leading(rest)
        not String.contains?(trimmed, "[") and match?(":" <> _, rest_trimmed)

      _ ->
        false
    end
  end

  # Returns true when `line` (after trimming) is just a bare atom like
  # `:field_b` or `:field_b,`.
  defp bare_atom_only?(line) do
    case String.trim(line) do
      ":" <> rest -> bare_atom_suffix?(rest)
      _ -> false
    end
  end

  defp bare_atom_suffix?(rest) do
    rest
    |> String.trim_trailing()
    |> remove_trailing_comma()
    |> String.trim_trailing()
    |> valid_atom_name?()
  end

  defp remove_trailing_comma(str) do
    len = byte_size(str)

    if len > 0 and :binary.at(str, len - 1) == ?, do
      binary_part(str, 0, len - 1)
    else
      str
    end
  end

  defp valid_atom_name?(""), do: false
  defp valid_atom_name?(<<"\"", _::binary>>), do: true

  defp valid_atom_name?(<<ch, rest::binary>>)
       when ch in ?a..?z or ch in ?A..?Z or ch == ?_ do
    rest
    |> String.to_charlist()
    |> Enum.all?(fn c -> c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ end)
  end

  defp valid_atom_name?(_), do: false

  # Returns a MapSet of line numbers that are part of a multi-line for/with
  # clause — i.e. continuation lines after the initial `<-` line that have
  # not yet been terminated by `do:` or a `do` block.
  #
  # This prevents false positives where guard lines like
  #
  #     for {name, job_data} <- state.jobs,
  #         job_data.status == :active,     ← bare comma, but a clause separator
  #         do: {name, job_data}
  #
  # are mistakenly flagged as Python multi-returns.
  defp for_with_clause_continuation_lines(lines) do
    {_, set} =
      lines
      |> Enum.with_index(1)
      |> Enum.reduce({false, MapSet.new()}, fn {line, line_no}, {in_clause, acc} ->
        trimmed = String.trim_leading(line)

        has_arrow = has_left_arrow_at_depth_zero?(line)
        has_do = has_do_keyword_at_depth_zero?(line)

        cond do
          # Line has `<-` at depth 0 but ALSO has `do:` → the clause ends
          # on this very line (e.g. `for x <- xs, do: x`). Mark as in-clause
          # for this line only, then stop.
          has_arrow and has_do ->
            {false, MapSet.put(acc, line_no)}

          # Line has `<-` at depth 0 → starts or continues a for/with clause
          has_arrow ->
            {true, MapSet.put(acc, line_no)}

          # Inside a clause and line has `do:` at depth 0 → clause ends here
          # (this line is still part of the clause, but the next won't be)
          in_clause and has_do ->
            {false, MapSet.put(acc, line_no)}

          # Inside a clause and line starts with `do` as a standalone keyword
          # (not `do:` which is handled above) → opens a block; NOT part of clause
          in_clause and starts_with_standalone_do?(trimmed) ->
            {false, acc}

          # Inside a clause and line starts with `end` → clause definitely over
          in_clause and starts_with_standalone_end?(trimmed) ->
            {false, acc}

          # Inside a clause → continuation line
          in_clause ->
            {true, MapSet.put(acc, line_no)}

          # Not inside a clause
          true ->
            {false, acc}
        end
      end)

    set
  end

  # Returns true when the line contains `do:` at depth 0 (a keyword option,
  # not inside parentheses/brackets/strings).
  defp has_do_keyword_at_depth_zero?(line) do
    check_do_keyword(String.to_charlist(line), 0, nil)
  end

  defp check_do_keyword([], _depth, _ctx), do: false
  defp check_do_keyword([?d, ?o, ?: | _rest], 0, nil), do: true

  # Inside string — skip
  defp check_do_keyword([q | rest], depth, ctx) when (ctx == ?" or ctx == ?') and q == ctx,
    do: check_do_keyword(rest, depth, nil)

  defp check_do_keyword([?\\, _ | rest], depth, ctx) when ctx == ?" or ctx == ?',
    do: check_do_keyword(rest, depth, ctx)

  defp check_do_keyword([_ | rest], depth, ctx) when ctx == ?" or ctx == ?',
    do: check_do_keyword(rest, depth, ctx)

  defp check_do_keyword([q | rest], depth, nil) when q == ?" or q == ?',
    do: check_do_keyword(rest, depth, q)

  # Delimiters
  defp check_do_keyword([ch | rest], depth, nil) when ch == ?( or ch == ?[ or ch == ?{,
    do: check_do_keyword(rest, depth + 1, nil)

  defp check_do_keyword([ch | rest], depth, nil) when ch == ?) or ch == ?] or ch == ?},
    do: check_do_keyword(rest, max(depth - 1, 0), nil)

  defp check_do_keyword([_ | rest], depth, ctx), do: check_do_keyword(rest, depth, ctx)

  # True when `trimmed` starts with `do` as a standalone keyword (not `do:`).
  # `do:` is caught by `has_do_keyword_at_depth_zero?` above; this handles the
  # multi-line `do ... end` block form.
  defp starts_with_standalone_do?(trimmed) do
    case trimmed do
      "do" -> true
      "do " <> _ -> true
      "do\t" <> _ -> true
      _ -> false
    end
  end

  defp starts_with_standalone_end?(trimmed) do
    case trimmed do
      "end" -> true
      "end " <> _ -> true
      "end\t" <> _ -> true
      "end\n" <> _ -> true
      _ -> false
    end
  end

  # ── Cross-line depth tracking ──────────────────────────────────────────

  # Returns `%{line_no => {depth_at_start_of_line, starts_inside_a_literal?}}`
  # by walking the entire source, accounting for comments, quoted strings and
  # heredocs.
  #
  # The literal flag matters as much as the depth: a heredoc's contents are
  # data, not code, and prose like `AST, then diffs the original` sits at depth
  # 0 while being nothing of the sort. Lines that start inside a string or
  # heredoc are never candidates.
  defp compute_line_starts(source) do
    source
    |> String.to_charlist()
    |> walk_depths(%{1 => {0, false}}, 0, 1, nil)
  end

  defp literal?({:str, _}), do: true
  defp literal?({:heredoc, _}), do: true
  defp literal?(_), do: false

  # EOF
  defp walk_depths([], depths, _depth, _line, _ctx), do: depths

  # Newline — record the state the next line starts in. A `#` comment ends at
  # the newline; a string or heredoc keeps running.
  defp walk_depths([?\n | rest], depths, depth, line, ctx) do
    next_ctx = if ctx == :comment, do: nil, else: ctx

    walk_depths(
      rest,
      Map.put(depths, line + 1, {depth, literal?(next_ctx)}),
      depth,
      line + 1,
      next_ctx
    )
  end

  # Inside a comment — skip until newline (handled above)
  defp walk_depths([_ | rest], depths, depth, line, :comment) do
    walk_depths(rest, depths, depth, line, :comment)
  end

  # Escape inside a string or heredoc — skip the escaped character
  defp walk_depths([?\\, escaped | rest], depths, depth, line, ctx)
       when elem(ctx, 0) == :str or elem(ctx, 0) == :heredoc do
    # If the escaped char is a newline, still track the line
    {depths, depth, line} =
      if escaped == ?\n,
        do: {Map.put(depths, line + 1, {depth, true}), depth, line + 1},
        else: {depths, depth, line}

    walk_depths(rest, depths, depth, line, ctx)
  end

  # Close heredoc — only the matching triple quote ends it, so an odd number of
  # lone `"` inside doc prose can no longer desync the whole rest of the file.
  defp walk_depths([q, q, q | rest], depths, depth, line, {:heredoc, q}) do
    walk_depths(rest, depths, depth, line, nil)
  end

  # Inside heredoc — skip
  defp walk_depths([_ | rest], depths, depth, line, {:heredoc, _} = ctx) do
    walk_depths(rest, depths, depth, line, ctx)
  end

  # Close string
  defp walk_depths([q | rest], depths, depth, line, {:str, q}) do
    walk_depths(rest, depths, depth, line, nil)
  end

  # Inside string — skip
  defp walk_depths([_ | rest], depths, depth, line, {:str, _} = ctx) do
    walk_depths(rest, depths, depth, line, ctx)
  end

  # A `?"` / `?'` character literal — the quote is a value, not a delimiter.
  defp walk_depths([??, q | rest], depths, depth, line, nil) when q == ?" or q == ?' do
    walk_depths(rest, depths, depth, line, nil)
  end

  # Start of comment
  defp walk_depths([?# | rest], depths, depth, line, nil) do
    walk_depths(rest, depths, depth, line, :comment)
  end

  # Start of heredoc
  defp walk_depths([q, q, q | rest], depths, depth, line, nil)
       when q == ?" or q == ?' do
    walk_depths(rest, depths, depth, line, {:heredoc, q})
  end

  # Start of string
  defp walk_depths([q | rest], depths, depth, line, nil)
       when q == ?" or q == ?' do
    walk_depths(rest, depths, depth, line, {:str, q})
  end

  # Open delimiter
  defp walk_depths([ch | rest], depths, depth, line, nil)
       when ch == ?( or ch == ?[ or ch == ?{ do
    walk_depths(rest, depths, depth + 1, line, nil)
  end

  # Close delimiter
  defp walk_depths([ch | rest], depths, depth, line, nil)
       when ch == ?) or ch == ?] or ch == ?} do
    walk_depths(rest, depths, max(depth - 1, 0), line, nil)
  end

  # Any other character
  defp walk_depths([_ | rest], depths, depth, line, ctx) do
    walk_depths(rest, depths, depth, line, ctx)
  end

  # ── Bare-comma detection (single-line, starting from depth 0) ─────────

  # Returns true when the line contains `<-` at depth 0, signalling a
  # `with`/`for` clause whose commas are clause separators, not bare
  # multi-returns.
  defp has_left_arrow_at_depth_zero?(line) do
    check_left_arrow(String.to_charlist(line), 0, nil)
  end

  # Found `<-` at depth 0 outside a string
  defp check_left_arrow([?<, ?- | _rest], 0, nil), do: true

  # EOF
  defp check_left_arrow([], _depth, _ctx), do: false

  # Newline
  defp check_left_arrow([?\n | rest], depth, _ctx) do
    check_left_arrow(rest, depth, nil)
  end

  # Inside comment — skip
  defp check_left_arrow([_ | rest], depth, :comment) do
    check_left_arrow(rest, depth, :comment)
  end

  # Escape inside string — skip escaped character
  defp check_left_arrow([?\\, _escaped | rest], depth, ctx)
       when ctx == ?" or ctx == ?' do
    check_left_arrow(rest, depth, ctx)
  end

  # Close string
  defp check_left_arrow([q | rest], depth, ctx)
       when (ctx == ?" or ctx == ?') and q == ctx do
    check_left_arrow(rest, depth, nil)
  end

  # Inside string — skip
  defp check_left_arrow([_ | rest], depth, ctx)
       when ctx == ?" or ctx == ?' do
    check_left_arrow(rest, depth, ctx)
  end

  # Start of comment
  defp check_left_arrow([?# | rest], depth, nil) do
    check_left_arrow(rest, depth, :comment)
  end

  # Start of string
  defp check_left_arrow([q | rest], depth, nil)
       when q == ?" or q == ?' do
    check_left_arrow(rest, depth, q)
  end

  # Open delimiter
  defp check_left_arrow([ch | rest], depth, nil)
       when ch == ?( or ch == ?[ or ch == ?{ do
    check_left_arrow(rest, depth + 1, nil)
  end

  # Close delimiter
  defp check_left_arrow([ch | rest], depth, nil)
       when ch == ?) or ch == ?] or ch == ?} do
    check_left_arrow(rest, max(depth - 1, 0), nil)
  end

  # Any other character
  defp check_left_arrow([_ | rest], depth, ctx) do
    check_left_arrow(rest, depth, ctx)
  end

  # Returns true when the line contains `|` at depth 0 that is a struct-update
  # pipe (not `||` or `|>`).  A bare `|` at depth 0 with keyword entries is
  # valid `struct | key: val, ...` syntax; the commas are keyword separators,
  # not bare multi-returns.
  defp has_struct_pipe_at_depth_zero?(line) do
    check_struct_pipe(String.to_charlist(line), 0, nil)
  end

  # Found `|` at depth 0 outside a string — check it is NOT `||` or `|>`
  defp check_struct_pipe([?| | rest], 0, nil) do
    case rest do
      # `||` — logical OR, not struct-update pipe
      [?| | _] -> false
      # `|>` — pipe operator, not struct-update pipe
      [?> | _] -> false
      _ -> true
    end
  end

  # EOF
  defp check_struct_pipe([], _depth, _ctx), do: false

  # Inside comment — skip
  defp check_struct_pipe([_ | rest], depth, :comment) do
    check_struct_pipe(rest, depth, :comment)
  end

  # Escape inside string — skip escaped character
  defp check_struct_pipe([?\\, _escaped | rest], depth, ctx)
       when ctx == ?" or ctx == ?' do
    check_struct_pipe(rest, depth, ctx)
  end

  # Close string
  defp check_struct_pipe([q | rest], depth, ctx)
       when (ctx == ?" or ctx == ?') and q == ctx do
    check_struct_pipe(rest, depth, nil)
  end

  # Inside string — skip
  defp check_struct_pipe([_ | rest], depth, ctx)
       when ctx == ?" or ctx == ?' do
    check_struct_pipe(rest, depth, ctx)
  end

  # Start of comment
  defp check_struct_pipe([?# | rest], depth, nil) do
    check_struct_pipe(rest, depth, :comment)
  end

  # Start of string
  defp check_struct_pipe([q | rest], depth, nil)
       when q == ?" or q == ?' do
    check_struct_pipe(rest, depth, q)
  end

  # Open delimiter
  defp check_struct_pipe([ch | rest], depth, nil)
       when ch == ?( or ch == ?[ or ch == ?{ do
    check_struct_pipe(rest, depth + 1, nil)
  end

  # Close delimiter
  defp check_struct_pipe([ch | rest], depth, nil)
       when ch == ?) or ch == ?] or ch == ?} do
    check_struct_pipe(rest, max(depth - 1, 0), nil)
  end

  # Any other character
  defp check_struct_pipe([_ | rest], depth, ctx) do
    check_struct_pipe(rest, depth, ctx)
  end

  # ── Fix helpers ────────────────────────────────────────────────────────

  defp fix_line(line) do
    case wrapped_line(line) do
      {:ok, fixed} -> fixed
      :error -> line
    end
  end

  # A line is a comment when its first non-whitespace character is `#`.
  defp comment_line?(line) do
    case String.trim_leading(line) do
      <<?#, _::binary>> -> true
      _ -> false
    end
  end

  # Split a string into {leading_whitespace, rest}.
  defp split_leading_ws(str) do
    trimmed = String.trim_leading(str)
    len = byte_size(str) - byte_size(trimmed)
    {binary_part(str, 0, len), trimmed}
  end

  # Split `line` at every comma that sits at depth 0. Returns a list of
  # segments — one element means no bare comma was found.
  #
  # Three lookaheads prevent over-firing:
  #   1. Keyword syntax — if the next non-space text starts with a keyword key
  #      (`word:` or `:"string":`), the comma is a keyword entry separator, not
  #      a bare multi-return. Keep it with the current segment.
  #   2. Catch/rescue clause — if `->` appears before the next depth-zero comma,
  #      the comma separates patterns in a clause head, not a bare multi-return.
  #   3. Mismatched delimiters — if a close delimiter doesn't match the last
  #      open delimiter (e.g. `)` closing a `{`), the line has a different kind
  #      of syntax error, not a Python multi-return. Skip splitting.
  defp split_at_depth_zero_commas(line) do
    chars = String.to_charlist(line)
    # Track remaining chars so the lookahead at each comma is accurate.
    # `stack` records the type of each open delimiter so we can detect mismatches.
    {segments, current, _depth, _in_str, _remaining, _stack, _mismatched} =
      Enum.reduce(chars, {[], [], 0, nil, safe_tl(chars), [], false}, fn ch,
                                                                         {segs, cur, depth,
                                                                          in_str, remaining,
                                                                          stack, mismatched} ->
        tail = safe_tl(remaining)

        cond do
          # Inside a string/char literal — skip until closing quote
          in_str != nil ->
            case ch do
              ^in_str -> {segs, cur ++ [ch], depth, nil, tail, stack, mismatched}
              ?\\ -> {segs, cur ++ [ch], depth, in_str, tail, stack, mismatched}
              _ -> {segs, cur ++ [ch], depth, in_str, tail, stack, mismatched}
            end

          # Start of a string or char literal
          ch in [?", ?'] ->
            {segs, cur ++ [ch], depth, ch, tail, stack, mismatched}

          # Open delimiter — increase depth, record which delimiter opened
          ch in [?(, ?[, ?{] ->
            {segs, cur ++ [ch], depth + 1, nil, tail, [ch | stack], mismatched}

          # Close delimiter — check if it matches the last open delimiter
          ch in [?), ?], ?}] ->
            {new_depth, new_stack, new_mismatched} =
              case stack do
                [opener | rest_stack]
                when (opener == ?( and ch == ?)) or
                       (opener == ?[ and ch == ?]) or
                       (opener == ?{ and ch == ?}) ->
                  {max(depth - 1, 0), rest_stack, mismatched}

                [_opener | rest_stack] ->
                  # Mismatched close delimiter (e.g. `)` closing a `{`)
                  {max(depth - 1, 0), rest_stack, true}

                [] ->
                  # Close without open — underflow
                  {0, [], true}
              end

            {segs, cur ++ [ch], new_depth, nil, tail, new_stack, new_mismatched}

          # Bare comma at depth 0 — split here unless a keyword key, arrow,
          # function-call-without-parens, block-closing `end`, or mismatched
          # delimiter precedes it.
          ch == ?, and depth == 0 ->
            if mismatched or keyword_or_arrow_ahead?(remaining) or function_call_before?(cur) or
                 block_end_before?(cur) do
              # Keep comma with current segment (keyword entry, clause pattern,
              # paren-less function call like `raise ArgumentError, "msg"`,
              # or mismatched delimiter where the real fix is the delimiter)
              {segs, cur ++ [ch], 0, nil, tail, stack, mismatched}
            else
              {segs ++ [cur], [], 0, nil, tail, stack, mismatched}
            end

          # Any other character
          true ->
            {segs, cur ++ [ch], depth, nil, tail, stack, mismatched}
        end
      end)

    # Append the final segment
    segments ++ [current]
  end

  defp safe_tl([]), do: []
  defp safe_tl([_ | t]), do: t

  # Returns true when, after the current comma, the next non-space text is a
  # keyword key (`word:` or `:"string":`) OR `->` appears before the next
  # depth-zero comma.
  defp keyword_or_arrow_ahead?(remaining_chars) do
    # Skip whitespace after the comma
    after_ws = Enum.drop_while(remaining_chars, &(&1 == ?\s))

    case after_ws do
      [] ->
        false

      # Atom key like :exit — not a keyword entry, check for arrow
      [?: | _rest] ->
        arrow_ahead?(after_ws)

      # Possible keyword key: word_char+
      [ch | _] when ch in ?a..?z or ch in ?A..?Z or ch == ?_ ->
        keyword_ahead?(after_ws) or arrow_ahead?(after_ws)

      _ ->
        arrow_ahead?(after_ws)
    end
  end

  # Returns true when the accumulated text before a depth-zero comma starts
  # with a lowercase identifier followed by whitespace and then content (not
  # `=`).  This indicates a paren-less function call, e.g.:
  #
  #     raise ArgumentError, "msg"  →  current = 'raise ArgumentError'
  #     send dest, msg              →  current = 'send dest'
  #
  # Without this check the rule would wrap these in a tuple, producing
  # `{raise ArgumentError, "msg"}` which is a syntax error.
  defp function_call_before?(current_chars) do
    case Enum.drop_while(current_chars, &(&1 == ?\s or &1 == ?\t)) do
      [ch | rest] when ch in ?a..?z or ch in ?A..?Z or ch == ?_ ->
        check_call_after_identifier(rest)

      # Atom-prefixed module call like `:ets.new arg1, arg2` or `:timer.tc fun, arg`
      [?: | rest] ->
        case Enum.drop_while(rest, &(&1 == ?\s or &1 == ?\t)) do
          [ch | _] when ch in ?a..?z or ch in ?A..?Z or ch == ?_ ->
            # Consume the atom name and optional .function
            {_atom_id, after_atom} =
              Enum.split_while(rest, fn c ->
                c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ or c == ?.
              end)

            after_ws = Enum.drop_while(after_atom, &(&1 == ?\s or &1 == ?\t))

            case after_ws do
              [] -> false
              [?= | _] -> false
              _ -> true
            end

          _ ->
            false
        end

      _ ->
        false
    end
  end

  # Returns true when the accumulated text before a depth-zero comma ends with
  # the block-closing keyword `end`.  This prevents the rule from misidentifying
  # `end, arg` inside a paren-less call like:
  #
  #     Enum.sort_by list, fn item -> item.value end, direction
  #
  # where `end` closes the `fn` block and the comma separates function args,
  # not a Python multi-return.
  defp block_end_before?(current_chars) do
    # Trim trailing whitespace from current_chars
    trimmed =
      current_chars
      |> Enum.reverse()
      |> Enum.drop_while(&(&1 == ?\s or &1 == ?\t))
      |> Enum.reverse()

    # Check if trimmed ends with `end` as a standalone keyword
    case Enum.reverse(trimmed) do
      [?d, ?n, ?e] -> true
      [?d, ?n, ?e, ch | _] when ch == ?\s or ch == ?\t -> true
      _ -> false
    end
  end

  # Shared logic after an identifier has been consumed — check if it looks
  # like a paren-less function call (identifier followed by whitespace and
  # then arguments, not an assignment).
  defp check_call_after_identifier(rest) do
    # Consume the identifier (letters, digits, underscores, dots)
    {_id, after_id} =
      Enum.split_while(rest, fn c ->
        c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ or c == ?.
      end)

    # Skip whitespace after the identifier
    after_ws = Enum.drop_while(after_id, &(&1 == ?\s or &1 == ?\t))

    # Must have content after the identifier, and it must not be an
    # assignment (which would indicate `var = expr, ...` not a function call)
    case after_ws do
      [] -> false
      [?= | _] -> false
      _ -> true
    end
  end

  # Check if `chars` starts with a keyword key pattern: word+ `:` or `:"` string `":`
  defp keyword_ahead?(chars) do
    # Consume word characters
    {word, rest} =
      Enum.split_while(chars, fn ch ->
        ch in ?a..?z or ch in ?A..?Z or ch in ?0..?9 or ch == ?_
      end)

    case rest do
      [?: | _] when word != [] -> true
      _ -> false
    end
  end

  # Check if `->` appears in `chars` before the next depth-zero comma.
  defp arrow_ahead?(chars), do: arrow_ahead?(chars, 0)

  defp arrow_ahead?([], _depth), do: false
  defp arrow_ahead?([?, | _], 0), do: false
  defp arrow_ahead?([?-, ?> | _rest], _depth), do: true

  defp arrow_ahead?([ch | rest], depth) when ch in [?(, ?[, ?{],
    do: arrow_ahead?(rest, depth + 1)

  defp arrow_ahead?([ch | rest], depth) when ch in [?), ?], ?}],
    do: arrow_ahead?(rest, max(depth - 1, 0))

  # Skip string/char literals
  defp arrow_ahead?([q | rest], depth) when q in [?", ?'],
    do: arrow_ahead?(skip_string(rest, q), depth)

  defp arrow_ahead?([_ | rest], depth), do: arrow_ahead?(rest, depth)

  defp skip_string([], _q), do: []
  defp skip_string([?\\, _ | rest], q), do: skip_string(rest, q)
  defp skip_string([q | rest], q), do: rest
  defp skip_string([_ | rest], q), do: skip_string(rest, q)
end
