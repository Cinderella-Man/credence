defmodule Credence.Syntax.NoMapArrowSyntaxInTupleBrace do
  @moduledoc """
  Repairs the common LLM syntax error where map arrow syntax (`=>`) is written
  inside tuple braces — Elixir rejects this during parsing.

  LLMs frequently emit `{"key" => value}` (map arrow syntax inside bare `{...}`)
  instead of `%{"key" => value}`. The `=>` operator is only valid inside `%{...}`
  map literals; bare `{...}` is tuple syntax and does not support `=>`, causing
  the Elixir parser to error with `syntax error before: '=>'`.

  The correct Elixir idiom is `%{"key" => value}` (a map literal), which supports
  `map["key"]` access, pattern-matching, and `Map.get/3`.

  ## Bad (won't parse — syntax error before: '=>')

      Jason.encode!({"error" => "File too large", "max_bytes" => 5_242_880})

  ## Good

      Jason.encode!(%{"error" => "File too large", "max_bytes" => 5_242_880})
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @impl true
  def analyze(source) do
    case Code.string_to_quoted(source) do
      {:error, {meta, _msg, token}} when is_list(meta) and token == "'=>'" ->
        [
          %Issue{
            rule: :no_map_arrow_syntax_in_tuple_brace,
            message: "syntax error before: '#{token}'",
            meta: %{line: Keyword.get(meta, :line)}
          }
        ]

      _ ->
        []
    end
  end

  @impl true
  def fix(source) do
    # Replace `{` not preceded by `%` or identifier chars, where the immediate
    # content looks like a map arrow entry (key followed by `=>`), with `%{`.
    #
    # The alternation order matters: identifiers and atoms are tried before
    # string literals to avoid regex backtracking issues with single/double
    # quote patterns.
    #
    # Matches: {"key" => ...}, {:atom => ...}, {var => ...}
    # Skips:   %{"key" => ...} (already a map), %Module{...} (struct)
    Regex.replace(
      ~r/(?<![A-Za-z0-9._%])\{(\s*(?:[a-zA-Z_]\w*|:[a-zA-Z_]\w*|"[^"]*")\s*=>)/,
      source,
      "%{\\1"
    )
  end
end
