defmodule Credence.Semantic.NoValidationRejectsInfinityForTimeout do
  @moduledoc """
  Fixes validation guards that reject `:infinity` for timeout values.

  LLMs commonly write validation guards like:

      unless is_integer(timeout) and timeout > 0 do
        raise ArgumentError, "timeout must be a positive integer"
      end

  This rejects `:infinity` (an atom), even when downstream code explicitly
  accepts it via `timeout != :infinity` branches (common in GenServer
  cleanup intervals, Process.send_after, etc.).

  The fix adds `or timeout == :infinity` to the validation condition and
  updates the error message to include `or :infinity`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "must be a positive integer"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_validation_rejects_infinity_for_timeout,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      patches = Credence.RuleHelpers.patches_from_ast_transform(ast, source, &transform_ast/1)

      case patches do
        [] ->
          source

        _ ->
          Sourceror.patch_string(source, patches)
      end
    else
      _ -> source
    end
  end

  defp transform_ast(ast) do
    Macro.postwalk(ast, fn
      {:unless, meta, [condition, kw_list]} = node ->
        case match_validation_condition(condition) do
          {:ok, var_name} ->
            new_condition = build_new_condition(condition, var_name)
            new_kw_list = update_raise_in_kw(kw_list)
            {:unless, meta, [new_condition, new_kw_list]}

          :error ->
            node
        end

      node ->
        node
    end)
  end

  defp match_validation_condition({:and, _, [is_int, gt_zero]}) do
    with {:ok, var1} <- match_is_integer(is_int),
         {:ok, var2} <- match_gt_zero(gt_zero),
         true <- var1 == var2 do
      {:ok, var1}
    else
      _ -> :error
    end
  end

  defp match_validation_condition(_), do: :error

  defp match_is_integer({:is_integer, _, [{var, _, nil}]}) when is_atom(var), do: {:ok, var}
  defp match_is_integer(_), do: :error

  defp match_gt_zero({:>, _, [{var, _, nil}, {:__block__, _, [0]}]}) when is_atom(var),
    do: {:ok, var}

  defp match_gt_zero(_), do: :error

  defp build_new_condition(condition, var_name) do
    {:or, [], [condition, {:==, [], [{var_name, [], nil}, {:__block__, [], [:infinity]}]}]}
  end

  defp update_raise_in_kw(kw_list) do
    Enum.map(kw_list, fn
      {{:__block__, meta, [:do]}, body} ->
        new_body = update_raise_in_body(body)
        {{:__block__, meta, [:do]}, new_body}

      other ->
        other
    end)
  end

  defp update_raise_in_body(body) do
    Macro.postwalk(body, fn
      {:__block__, meta, [message]} = node when is_binary(message) ->
        if String.contains?(message, @match_msg) do
          {:__block__, meta, [message <> " or :infinity"]}
        else
          node
        end

      node ->
        node
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
