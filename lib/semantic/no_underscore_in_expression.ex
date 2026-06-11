defmodule Credence.Semantic.NoUnderscoreInExpression do
  @moduledoc """
  Fixes compiler errors caused by using `_` in expression position,
  such as a tuple key in a for-comprehension body.

  The Elixir compiler rejects `_` in expression position:

      for _ <- 0..(n - 1), into: %{} do
        {_, :infinity}    # ← error: invalid use of _
      end

  The fix renames the `_` generator to a fresh variable (`idx`)
  and updates all references in the comprehension body:

      for idx <- 0..(n - 1), into: %{} do
        {idx, :infinity}
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, "invalid use of _") or
      String.contains?(msg, "redefining module Solution")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_underscore_in_expression,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    case parse(source) do
      {:ok, ast} ->
        transformed = transform_underscores(ast)

        if transformed == ast do
          source
        else
          patches = Credence.RuleHelpers.patches_from_diff(ast, transformed)

          case patches do
            [] -> source
            _ -> Sourceror.patch_string(source, patches)
          end
        end

      :error ->
        source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line

  defp parse(source) do
    {:ok, Sourceror.parse_string!(source)}
  rescue
    _ -> :error
  end

  defp transform_underscores(ast) do
    Macro.postwalk(ast, fn
      {:for, meta, args} = node ->
        if has_underscore_generator?(args) do
          {:for, meta, rename_underscore_in_for_args(args)}
        else
          node
        end

      node ->
        node
    end)
  end

  defp has_underscore_generator?(args) when is_list(args) do
    Enum.any?(args, fn
      {:<-, _, [{:_, _, nil}, _]} -> true
      _ -> false
    end)
  end

  defp rename_underscore_in_for_args(args) do
    Enum.map(args, fn
      {:<-, arrow_meta, [{:_, var_meta, nil}, range]} ->
        {:<-, arrow_meta, [{:idx, var_meta, nil}, range]}

      [{{:__block__, do_meta, [:do]}, body}] ->
        new_body =
          Macro.prewalk(body, fn
            {:_, u_meta, nil} -> {:idx, u_meta, nil}
            other -> other
          end)

        [{{:__block__, do_meta, [:do]}, new_body}]

      other ->
        other
    end)
  end
end
