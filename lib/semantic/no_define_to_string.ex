defmodule Credence.Semantic.NoDefineToString do
  @moduledoc """
  Fixes the compile error caused by defining `defp to_string/1`.

  LLMs frequently define a local `to_string/1` helper (a map-key normalizer)
  that conflicts with the auto-imported `Kernel.to_string/1`. The compiler
  emits:

      "imported Kernel.to_string/1 conflicts with local function"

  The fix renames the local function to `key_to_string` and updates all
  internal call sites.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "conflicts with local function"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_define_to_string,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:to_string, meta, args}, _acc when is_list(args) ->
            {{:key_to_string, meta, args}, true}

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
