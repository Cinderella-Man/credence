defmodule Credence.Semantic.FixFnArityInKeywordValue do
  @moduledoc """
  Fixes `function: :func/N` in keyword arguments passed to `raise`.

  LLMs write `raise FunctionClauseError, function: :push/4` using Elixir
  doc-notation `/N` for arity inside keyword args. Elixir parses `/` as
  `Kernel.//2`, producing `:push / 4` (atom ÷ integer) which fails compilation
  with:

      incompatible types given to Kernel.//2

  The fix splits `function: :foo/N` into `function: :foo, arity: N`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "incompatible types given to Kernel.//2"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_fn_arity_in_keyword_value,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:raise, raise_meta, [exception, kw_list]}, acc
          when is_list(kw_list) ->
            case fix_keyword_arity(kw_list) do
              {:ok, new_kw} -> {{:raise, raise_meta, [exception, new_kw]}, true}
              :unchanged -> {{:raise, raise_meta, [exception, kw_list]}, acc}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # Walk keyword pairs and split `function: :foo/N` into `function: :foo, arity: N`.
  defp fix_keyword_arity(kw_list) do
    {new_pairs, changed} =
      Enum.reduce(kw_list, {[], false}, fn
        {{:__block__, key_meta, [:function]} = key, {:/, _, [atom_node, int_node]}},
        {acc, _} ->
          # Extract the atom name and integer arity
          case {extract_atom(atom_node), extract_integer(int_node)} do
            {atom, arity} when is_atom(atom) and is_integer(arity) ->
              function_pair = {key, {:__block__, [token: inspect(atom)], [atom]}}

              arity_key =
                {:__block__, Keyword.put(key_meta, :format, :keyword), [:arity]}

              arity_pair = {arity_key, {:__block__, [token: to_string(arity)], [arity]}}
              {acc ++ [function_pair, arity_pair], true}

            _ ->
              {acc ++ [{key, {:/, [], [atom_node, int_node]}}], false}
          end

        pair, {acc, changed} ->
          {acc ++ [pair], changed}
      end)

    if changed, do: {:ok, new_pairs}, else: :unchanged
  end

  defp extract_atom({:__block__, _, [atom]}) when is_atom(atom), do: atom
  defp extract_atom(_), do: nil

  defp extract_integer({:__block__, _, [int]}) when is_integer(int), do: int
  defp extract_integer(_), do: nil

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
