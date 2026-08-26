defmodule Credence.Semantic.NoMapUpdateMissingKey do
  @moduledoc """
  Fixes the compiler warning where `%{var | key: value}` is used but the map
  literal assigned to `var` does not include `key`.

  LLMs frequently add keys to a map via `%{state | new_key: val}` (translating
  Python `dict[key] = val`), but Elixir map update syntax can only modify
  existing keys — missing keys cause "expected a map with key :X in map update
  syntax".

  The fix changes the failing update to `Map.put/3`, which can add a missing key.
  For example:

      state = %{counter: 0, data: []}
      {:ok, %{state | timer_ref: timer_ref}}

  becomes:

      state = %{counter: 0, data: []}
      {:ok, Map.put(state, :timer_ref, timer_ref)}

  ## Bad

      defmodule ExampleNMUMK do
        def setup do
          state = %{counter: 0, data: []}
          state = %{state | timer_ref: nil}
          state
        end
      end

  ## Good

      defmodule ExampleNMUMK do
        def setup do
          state = %{counter: 0, data: []}
          state = Map.put(state, :timer_ref, nil)
          state
        end
      end
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
  def fix(source, %{message: msg} = diagnostic) do
    with {:ok, key} <- extract_key(msg),
         {:ok, var} <- extract_var(msg),
         {:ok, ast} <- Sourceror.parse_string(source) do
      key_atom = String.to_atom(key)
      var_atom = String.to_atom(var)
      diagnostic_line = line(diagnostic)

      candidates =
        Macro.prewalk(ast, [], fn node, acc ->
          if matching_update?(node, var_atom, key_atom),
            do: {node, [node | acc]},
            else: {node, acc}
        end)
        |> elem(1)

      has_missing_literal? =
        Macro.prewalk(ast, false, fn node, found ->
          {node, found or missing_literal_assignment?(node, var_atom, key_atom)}
        end)
        |> elem(1)

      target =
        if has_missing_literal? do
          Enum.find(candidates, &(node_line(&1) == diagnostic_line)) ||
            if(length(candidates) == 1, do: hd(candidates))
        end

      {result, changed} =
        Macro.prewalk(ast, false, fn
          ^target = node, false when not is_nil(target) ->
            {replace_update(node, key_atom), true}

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

  defp matching_update?(
         {:%{}, _, [{:|, _, [{var_atom, _, nil}, pairs]}]},
         var_atom,
         key_atom
       ) do
    Enum.any?(pairs, &match?({{:__block__, _, [^key_atom]}, _}, &1))
  end

  defp matching_update?(_node, _var_atom, _key_atom), do: false

  defp missing_literal_assignment?(
         {:=, _, [{var_atom, _, nil}, {:%{}, _, pairs}]},
         var_atom,
         key_atom
       ) do
    not match?([{:|, _, _}], pairs) and
      not Enum.any?(pairs, &match?({{:__block__, _, [^key_atom]}, _}, &1))
  end

  defp missing_literal_assignment?(_node, _var_atom, _key_atom), do: false

  defp replace_update({:%{}, map_meta, [{:|, pipe_meta, [var, pairs]}]}, key_atom) do
    {missing, remaining} =
      Enum.split_with(pairs, &match?({{:__block__, _, [^key_atom]}, _}, &1))

    [{_key, value}] = missing

    base =
      if remaining == [], do: var, else: {:%{}, map_meta, [{:|, pipe_meta, [var, remaining]}]}

    key = {:__block__, [], [key_atom]}

    quote do
      Map.put(unquote(base), unquote(key), unquote(value))
    end
  end

  defp node_line({_, meta, _}) when is_list(meta), do: meta[:line]
  defp node_line(_), do: nil

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
