defmodule Credence.Semantic.NoHallucinatedPersistentTermFn do
  @moduledoc """
  Fixes code that hallucinates `:persistent_term.get_keys/0`.

  LLMs commonly hallucinate `:persistent_term.get_keys/0` (does not exist in
  Erlang's `persistent_term` module); the correct approach is
  `:persistent_term.get/0` which returns `[{key, value} | ...]`.

  The fix rewrites:

      keys = :persistent_term.get_keys()
      Enum.each(keys, fn key ->
        :persistent_term.erase(key)
      end)

  to the idiomatic:

      Enum.each(:persistent_term.get(), fn {key, _value} ->
        :persistent_term.erase(key)
      end)
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "clauses with the same name and arity (number of arguments) should be grouped together"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_hallucinated_persistent_term_fn,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:__block__, _meta, _statements} = node, false ->
            case try_transform_block(node) do
              {:ok, new_node} -> {new_node, true}
              :error -> {node, false}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # Match a block containing:
  #   var = :persistent_term.get_keys()
  #   Enum.each(var, fn key -> ... end)
  # Replace with:
  #   Enum.each(:persistent_term.get(), fn {key, _value} -> ... end)
  defp try_transform_block({:__block__, meta, statements}) do
    case find_get_keys_pattern(statements) do
      {:ok, transformed, rest} ->
        case rest do
          [] -> {:ok, transformed}
          _ -> {:ok, {:__block__, meta, [transformed | rest]}}
        end

      :error ->
        :error
    end
  end

  defp find_get_keys_pattern([
         {:=, _, [{var_name, _, nil}, get_keys_call]},
         {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, :each]}, call_meta,
          [{var_name2, _, nil}, fn_body]}
         | rest
       ])
       when var_name == var_name2 do
    if is_get_keys_call?(get_keys_call) do
      case transform_fn_pattern(fn_body) do
        {:ok, new_fn} ->
          new_get_call = build_get_call(get_keys_call)

          new_each =
            {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, :each]}, call_meta,
             [new_get_call, new_fn]}

          {:ok, new_each, rest}

        :error ->
          :error
      end
    else
      :error
    end
  end

  defp find_get_keys_pattern([first | rest]) do
    case find_get_keys_pattern(rest) do
      {:ok, transformed, remaining} -> {:ok, transformed, [first | remaining]}
      :error -> :error
    end
  end

  defp find_get_keys_pattern([]), do: :error

  defp is_get_keys_call?({{:., _, [{:__block__, _, [:persistent_term]}, :get_keys]}, _, []}),
    do: true

  defp is_get_keys_call?(_), do: false

  defp build_get_call(
         {{:., dot_meta, [{:__block__, block_meta, [:persistent_term]}, :get_keys]}, call_meta,
          _args}
       ) do
    {{:., dot_meta, [{:__block__, block_meta, [:persistent_term]}, :get]}, call_meta, []}
  end

  # Transform fn key -> ... end to fn {key, _value} -> ... end
  defp transform_fn_pattern(
         {:fn, fn_meta, [{:->, arrow_meta, [[{var_name, var_meta, nil}], body]}]}
       ) do
    new_pattern = [{:__block__, [], [{{var_name, var_meta, nil}, {:_value, [], nil}}]}]
    {:ok, {:fn, fn_meta, [{:->, arrow_meta, [new_pattern, body]}]}}
  end

  defp transform_fn_pattern(_), do: :error

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
