defmodule Credence.Semantic.PreferRescueBeforeCatch do
  @moduledoc """
  Fixes the compiler warning when `catch` appears before `rescue` in a `try` block.

  The compiler emits:

      "catch" should always come after "rescue" in try

  Reordering `rescue`-before-`catch` is behaviour-preserving: clause-matching
  order in `try` blocks is source-order-independent. The fix also removes a
  compiler warning that blocks `--warnings-as-errors`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "\"catch\" should always come after \"rescue\" in try"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :prefer_rescue_before_catch,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      result =
        Macro.postwalk(ast, fn
          {:try, meta, [clauses]} ->
            reorder_try_clauses(meta, clauses)

          node ->
            node
        end)

      Sourceror.to_string(result)
    else
      _ -> source
    end
  end

  defp reorder_try_clauses(meta, clauses) do
    catch_idx = Enum.find_index(clauses, &match?({{:__block__, _, [:catch]}, _}, &1))
    rescue_idx = Enum.find_index(clauses, &match?({{:__block__, _, [:rescue]}, _}, &1))

    if catch_idx && rescue_idx && catch_idx < rescue_idx do
      catch_clause = Enum.at(clauses, catch_idx)
      rescue_clause = Enum.at(clauses, rescue_idx)

      without =
        clauses
        |> Enum.with_index()
        |> Enum.reject(fn {_, i} -> i == catch_idx or i == rescue_idx end)
        |> Enum.map(fn {c, _} -> c end)

      {before, after_} = Enum.split(without, catch_idx)
      {:try, meta, [before ++ [rescue_clause, catch_clause] ++ after_]}
    else
      {:try, meta, [clauses]}
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
