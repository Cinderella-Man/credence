defmodule Credence.Semantic.NoListKeystoreThreeArgs do
  @moduledoc """
  Fixes calls to `List.keystore/3` by inserting `0` as the position argument.

  LLMs frequently confuse `List.keystore/4` with `List.keyfind/3`, writing:

      List.keystore(list, key, new_tuple)

  which should be:

      List.keystore(list, 0, key, new_tuple)

  The compiler emits:

      List.keystore/3 is undefined or private. Did you mean: * keystore/4

  When the third argument is a tuple whose first element equals the search key,
  the missing position is `0` — the only semantically correct reading.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "List.keystore/3"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_list_keystore_three_args,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {{:., dot_meta, [{:__aliases__, alias_meta, [:List]}, :keystore]}, call_meta, args},
          _acc
          when length(args) == 3 ->
            [a, b, c] = args
            zero = {:__block__, [token: "0"], [0]}
            new_node = {{:., dot_meta, [{:__aliases__, alias_meta, [:List]}, :keystore]}, call_meta, [a, zero, b, c]}
            {new_node, true}

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
