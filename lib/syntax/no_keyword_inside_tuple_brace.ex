defmodule Credence.Syntax.NoKeywordInsideTupleBrace do
  @moduledoc """
  Repairs the common LLM syntax error where keyword list syntax is written
  inside tuple braces — Elixir rejects this during parsing.

  LLMs frequently emit `{key: val, key2: val2}` (Python/JS dict literal) syntax
  inside list elements or other contexts, causing the Elixir parser to error with
  "unexpected keyword list inside tuple. Did you mean to write a map (using %{...})
  or a list (using [...]) instead?"

  The correct Elixir idiom is `%{key: val, key2: val2}` (map with atom keys),
  which supports identical `map.key` access, pattern-matching, and `Map.put/3`.

  ## Bad (won't parse — syntax error)

      data = [{step_name: name, compensation: compensation}]

  ## Good

      data = [%{step_name: name, compensation: compensation}]
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @error_fragment "unexpected keyword list inside tuple"

  @impl true
  def analyze(source) do
    case Code.string_to_quoted(source) do
      {:error, {meta, msg, _token}} when is_list(meta) ->
        if String.contains?(to_string(msg), @error_fragment) do
          [
            %Issue{
              rule: :no_keyword_inside_tuple_brace,
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
    # Replace `{atom_key: …}` with `%{atom_key: …}`. The regex matches a `{`
    # that is NOT already preceded by `%` (so valid `%{…}` maps are left alone)
    # and is NOT preceded by identifier characters (letters, digits, `_`, `.`),
    # which would indicate struct syntax `%Module{…}`.
    #
    # In Elixir struct patterns like `%Plug.Conn{assigns: %{...}}`, the `{` after
    # `Conn` must not be touched — it is struct syntax, not a tuple brace.
    #
    # A single `{atom: val}` is also illegal inside Elixir braces, so we do not
    # require a comma — any `{atom_key: …}` qualifies.
    Regex.replace(~r/(?<![A-Za-z0-9._%])\{(\s*[a-z_]\w*:\s)/, source, "%{\\1")
  end
end
