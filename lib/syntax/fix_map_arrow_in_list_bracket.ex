defmodule Credence.Syntax.FixMapArrowInListBracket do
  @moduledoc """
  Repairs the common LLM syntax error where map arrow syntax (`=>`) is written
  inside list brackets in typespecs — Elixir rejects this during parsing.

  LLMs frequently emit `[atom() => any()]` (map arrow syntax inside `[...]`)
  instead of the correct `[{atom(), any()}]`. The `=>` operator is only valid
  inside `%{...}` map literals; bare `[...]` with `=>` is a syntax error in
  Elixir, producing `syntax error before: '=>'`.

  This is a companion to `NoMapArrowSyntaxInTupleBrace` which handles the
  `{k => v}` variant inside tuple braces.

  ## Bad (won't parse — syntax error before: '=>')

      @spec new() :: [atom() => any()]

  ## Good

      @spec new() :: [{atom(), any()}]
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @impl true
  def analyze(source) do
    case Code.string_to_quoted(source) do
      {:error, {meta, _msg, token}} when is_list(meta) and token == "'=>'" ->
        if source =~ ~r/\[.*=>.*\]/ do
          [
            %Issue{
              rule: :fix_map_arrow_in_list_bracket,
              message: "syntax error before: '#{token}'",
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
    Regex.replace(~r/\[([^\[\]]*?)\s*=>\s*([^\[\]]*)\]/, source, fn _full, key, value ->
      "[{#{key}, #{value}}]"
    end, global: true)
  end
end
