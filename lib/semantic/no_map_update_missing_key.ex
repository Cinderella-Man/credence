defmodule Credence.Semantic.NoMapUpdateMissingKey do
  @moduledoc """
  Fixes the compiler warning where `%{var | key: value}` is used but the map
  literal assigned to `var` does not include `key`.

  LLMs frequently add keys to a map via `%{state | new_key: val}` (translating
  Python `dict[key] = val`), but Elixir map update syntax can only modify
  existing keys — missing keys cause "expected a map with key :X in map update
  syntax".

  The fix adds the missing key with a `nil` default to the original map literal.
  For example:

      state = %{counter: 0, data: []}
      {:ok, %{state | timer_ref: timer_ref}}

  becomes:

      state = %{counter: 0, data: [], timer_ref: nil}
      {:ok, %{state | timer_ref: timer_ref}}
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_prefix "expected a map with key :"
  @match_suffix "in map update syntax"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_prefix) and String.contains?(msg, @match_suffix)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    key_name = extract_key_name(diagnostic.message)

    %Issue{
      rule: :no_map_update_missing_key,
      message:
        "map update uses key :#{key_name} but the original map literal does not include it",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    with {:ok, key} <- extract_key(msg),
         {:ok, var} <- extract_var(msg),
         {:ok, ast} <- Sourceror.parse_string(source) do
      key_atom = String.to_atom(key)
      var_atom = String.to_atom(var)

      {result, changed} =
        Macro.prewalk(ast, false, fn
          {:=, meta, [{^var_atom, vmeta, nil}, {:%{}, map_meta, pairs}]} = node, acc ->
            cond do
              # Skip `var = %{var | ...}` update-reassignments: their pairs are a
              # single `:|` node, not literal key/value pairs. Appending a pair
              # there mangles the update into `%{var | [k: nil], k: nil}`.
              update_map?(pairs) ->
                {node, acc}

              key_exists?(pairs, key_atom) ->
                {node, acc}

              true ->
                new_pair = build_keyword_pair(key_atom)

                {{:=, meta, [{var_atom, vmeta, nil}, {:%{}, map_meta, pairs ++ [new_pair]}]},
                 true}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(result), else: source
    else
      _ -> source
    end
  end

  defp extract_key(msg) do
    case Regex.run(~r/expected a map with key :(\w+) in map update syntax/, msg) do
      [_, key] -> {:ok, key}
      _ -> :error
    end
  end

  defp extract_var(msg) do
    case Regex.run(~r/%\{(\w+)\s*\|/, msg) do
      [_, var] -> {:ok, var}
      _ -> :error
    end
  end

  defp extract_key_name(msg) do
    case extract_key(msg) do
      {:ok, key} -> key
      _ -> "unknown"
    end
  end

  defp update_map?([{:|, _, _}]), do: true
  defp update_map?(_), do: false

  defp key_exists?(pairs, key_atom) do
    Enum.any?(pairs, fn
      {{:__block__, _, [^key_atom]}, _} -> true
      _ -> false
    end)
  end

  defp build_keyword_pair(key_atom) do
    {
      {:__block__, [format: :keyword, trailing_comments: [], leading_comments: []], [key_atom]},
      {:__block__, [trailing_comments: [], leading_comments: []], [nil]}
    }
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
