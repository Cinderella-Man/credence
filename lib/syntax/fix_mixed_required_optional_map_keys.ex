defmodule Credence.Syntax.FixMixedRequiredOptionalMapKeys do
  @moduledoc """
  Fixes map typespecs that mix required keyword keys with optional arrow entries.

  LLMs frequently emit typespecs like `%{state: atom(), optional(atom()) => any()}`
  which is a parse error in Elixir — keyword entries must come last in maps, so
  mixing required keyword keys (`key: type`) with optional arrow entries
  (`optional(k) => v`) triggers:

      unexpected expression after keyword list

  The fix drops the redundant required keyword keys since `optional(atom())`
  already covers arbitrary key matching. The result is a valid, compilable
  typespec: `%{optional(atom()) => any()}`.

  ## Bad (won't parse)

      @type record :: %{state: atom(), optional(atom()) => any()}

  ## Good

      @type record :: %{optional(atom()) => any()}
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @error_prefix "unexpected expression after keyword list"

  @impl true
  def analyze(source) do
    case Code.string_to_quoted(source) do
      {:error, {_meta, msg, _token}} when is_binary(msg) ->
        if String.starts_with?(msg, @error_prefix) and
             Regex.match?(~r/%\{[^}]*\b\w+:\s.*optional\(/s, source) do
          [
            %Issue{
              rule: :fix_mixed_required_optional_map_keys,
              message:
                "Mixing required keyword keys with optional arrow entries in a map typespec. " <>
                  "Drop the required keys — `optional(k) => v` already covers them.",
              meta: %{}
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
    fixed =
      Regex.replace(~r/%\{.*?optional\(/s, source, "%{optional(")

    if fixed != source, do: fixed, else: source
  rescue
    _ -> source
  end
end
