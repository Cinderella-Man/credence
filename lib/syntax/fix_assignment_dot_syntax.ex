defmodule Credence.Syntax.FixAssignmentDotSyntax do
  @moduledoc """
  Fixes the extra-dot-after-`=` syntax error LLMs (especially Qwen) produce.

  `var =.function_call()` is a parse-breaking syntax error. The LLM inserts a
  dot between `=` and the function name. The fix removes the spurious dot so
  the assignment becomes `var = function_call()`.

  ## Detected pattern

  A line of the form `<indent><var> =.<identifier>` where `=` is followed
  immediately (or with a single space) by a `.` and then an identifier.

      ref =.make_ref()        →  ref = make_ref()
      x =.some_function(a)    →  x = some_function(a)

  ## Not flagged

  - Valid assignments without the extra dot (`ref = make_ref()`)
  - Comments (`# ref =.make_ref()`)
  - String literals (`msg = "=.not_a_dot"`)
  - A **digit** after the dot (`rate = .05`, `x =.5e3`) — see below

  ## Why a digit after the dot is left alone

  `.5` after `=` is far more likely a Python float literal (`0.5`) than a
  spurious dot before a call: Elixir has no `.5` literal, so the line is
  broken either way, but the two readings disagree about the *value*. Dropping
  the dot turns `rate = .05` into `rate = 05`, which parses — as the integer
  `5`, a different value of a different type — and turns `x =.5e3` into
  `x = 5e3`, which doesn't parse at all. Neither is a same-answer rewrite, so
  the rule requires the character after the dot to start an identifier
  (`a-z`, `A-Z`, `_`). Python-style float literals are a separate problem for
  a separate rule.
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  # Match: optional leading whitespace, a variable name, `=`, an optional space
  # before a dot, then the start of an identifier.  The dot after `=` is the
  # fault.  The lookahead deliberately excludes digits (see the moduledoc).
  # The capture group holds the prefix up to and including `=` (no trailing space)
  # so the callback can append exactly one space.
  @bad_pattern ~r/^(\s*[a-zA-Z_]\w*\s*=)\s?\.(?=[a-zA-Z_])/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if comment_line?(line) do
        []
      else
        case Regex.run(@bad_pattern, line) do
          [_match, _capture] -> [build_issue(line_no)]
          nil -> []
        end
      end
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      if comment_line?(line) do
        line
      else
        Regex.replace(@bad_pattern, line, fn _match, prefix -> "#{prefix} " end)
      end
    end)
  end

  defp comment_line?(line), do: Regex.match?(~r/^\s*#/, line)

  defp build_issue(line_no) do
    %Issue{
      rule: :fix_assignment_dot_syntax,
      message: "Extra dot after `=` in assignment — use `var = fun()` instead of `var =.fun()`.",
      meta: %{line: line_no}
    }
  end
end
