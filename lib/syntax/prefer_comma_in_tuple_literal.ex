defmodule Credence.Syntax.PreferCommaInTupleLiteral do
  @moduledoc """
  Repairs the common LLM syntax error where a comma is missing between
  elements in a tuple literal, causing a parse error.

  LLMs frequently omit the comma after an atom in a 2-tuple, e.g.
  `{:noreply state}` instead of `{:noreply, state}`. This causes the
  Elixir parser to report "syntax error before: state".

  The fix inserts the missing comma between the atom and the following
  element within bare tuple braces.

  ## Bad (won't parse)

      {:noreply state}

  ## Good

      {:noreply, state}
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  # Matches `{atom value}` where atom is like `:noreply` and value is not a
  # comma or closing brace.  The negative lookbehind avoids matching `%{…}`
  # maps and `%Module{…}` structs.
  @fix_pattern ~r/(?<![A-Za-z0-9_.%])(\{)(:[a-z_]\w*)\s+(?=[^,}\s])/

  @impl true
  def analyze(source) do
    case Code.string_to_quoted(source) do
      {:error, {meta, msg, _token}} when is_list(meta) ->
        msg_str = to_string(msg)

        if String.contains?(msg_str, "syntax error before:") and
             Regex.match?(@fix_pattern, source) do
          [
            %Issue{
              rule: :prefer_comma_in_tuple_literal,
              message: msg_str,
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
    fixed = Regex.replace(@fix_pattern, source, "\\1\\2, ")
    if fixed == source, do: source, else: fix(fixed)
  end
end
