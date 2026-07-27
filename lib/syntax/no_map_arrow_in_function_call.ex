defmodule Credence.Syntax.NoMapArrowInFunctionCall do
  @moduledoc """
  Repairs the common LLM syntax error where map arrow syntax (`=>`) is used
  as a function argument after an empty map literal `%{}`.

  LLMs frequently emit `Map.put(%{}, key => value)` — the `=>` arrow is only
  valid inside `%{...}` map literals, not as a function argument. The parser
  rejects this with `syntax error before: '=>'`.

  The correct Elixir idiom is the three-argument form `Map.put(%{}, key, value)`.

  ## Bad (won't parse — syntax error before: '=>')

      Map.put(%{}, key => value)

  ## Good

      Map.put(%{}, key, value)
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @impl true
  def analyze(source) do
    case Code.string_to_quoted(source) do
      {:error, {meta, _msg, token}} when is_list(meta) and token == "'=>'" ->
        # Only flag when the source contains `%{}` (empty map literal) followed
        # by an arrow expression — distinguishes from `{"k" => v}` (tuple brace)
        # which is handled by NoMapArrowSyntaxInTupleBrace.
        if source =~ ~r/%\{\}\s*,\s*\S+\s*=>/ do
          [
            %Issue{
              rule: :no_map_arrow_in_function_call,
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
    # Replace `expr => value` after `%{}` with `expr, value`.
    # This converts e.g. `Map.put(%{}, key => value)` to `Map.put(%{}, key, value)`.
    #
    # The regex matches:
    #   - `%{}` literal
    #   - whitespace (required — the arrow is a separate argument)
    #   - the key expression (lazy match up to `=>`)
    #   - optional whitespace, `=>`, optional whitespace
    #
    # And replaces with `%{}, <key>, ` — the value that follows is left in place.
    Regex.replace(~r/(%\{\}\s*,\s*)(.+?)\s*=>\s*/, source, "\\1\\2, ")
  end
end
