defmodule Credence.Semantic.FixHallucinatedEnumTakeDropRight do
  @moduledoc """
  Fixes the compile warning caused by calling `Enum.take_right/2` or `Enum.drop_right/2`.

  These functions do not exist in Elixir — they are common LLM hallucinations.
  The compiler emits:

      "Enum.take_right/2 is undefined or private"
      "Enum.drop_right/2 is undefined or private"

  The fix replaces `Enum.take_right(list, n)` with `Enum.take(list, -n)` and
  `Enum.drop_right(list, n)` with `Enum.drop(list, -n)`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @hallucinated_fns ~w(take_right drop_right)a

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    (String.contains?(msg, "Enum.take_right/") or String.contains?(msg, "Enum.drop_right/")) and
      (String.contains?(msg, "undefined or private") or
         String.contains?(msg, "undefined function"))
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_hallucinated_enum_take_drop_right,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, fn_name]}, call_meta, [list, n]},
          _acc
          when fn_name in @hallucinated_fns ->
            new_fn = String.to_atom(String.replace(Atom.to_string(fn_name), "_right", ""))
            negated_n = {:-, [line: get_in(dot_meta, [:line]) || get_in(alias_meta, [:line])], [n]}
            {{{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, new_fn]}, call_meta, [list, negated_n]}, true}

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
