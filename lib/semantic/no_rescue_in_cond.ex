defmodule Credence.Semantic.NoRescueInCond do
  @moduledoc """
  Fixes the compiler error when `rescue` or `catch` clauses appear inside a
  `cond` block.

  The compiler emits:

      "unexpected option :rescue in \"cond\""
      "unexpected option :catch in \"cond\""

  LLMs frequently write `rescue`/`catch` inside `cond` blocks (confusing them
  with `try`), which is a compile error. The fix wraps the `cond` in a `try`
  block and moves the `rescue`/`catch` clauses into the `try`. Any `after`/`else`
  clauses on the same `cond` — equally invalid there, equally valid on `try` —
  ride along, so the rewrite compiles in one pass.

  ## Bad (compiles with error)

      cond do
        true -> :ok
      rescue
        e -> {:error, e}
      end

  ## Good

      try do
        cond do
          true -> :ok
        end
      rescue
        e -> {:error, e}
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_rescue "unexpected option :rescue in \"cond\""
  @match_catch "unexpected option :catch in \"cond\""

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_rescue) or String.contains?(msg, @match_catch)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_rescue_in_cond,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {result, 0} = Macro.traverse(ast, 0, &rewrite_cond/2, &leave_quote/2)

      if result == ast do
        source
      else
        Sourceror.to_string(result)
      end
    else
      _ -> source
    end
  end

  defp rewrite_cond({:quote, _, _} = node, quote_depth), do: {node, quote_depth + 1}

  defp rewrite_cond({:cond, meta, [opts]} = node, 0) when is_list(opts) do
    {bad, good} = extract_bad_opts(opts)

    if Enum.any?(bad, &trigger_opt?/1) do
      new_cond = {:cond, meta, [good]}

      {{:try, meta,
        [
          [
            {{:__block__, [], [:do]}, new_cond} | bad
          ]
        ]}, 0}
    else
      {node, 0}
    end
  end

  defp rewrite_cond(node, quote_depth), do: {node, quote_depth}

  defp leave_quote({:quote, _, _} = node, quote_depth), do: {node, quote_depth - 1}
  defp leave_quote(node, quote_depth), do: {node, quote_depth}

  # `after` and `else` are also invalid in `cond` but valid in `try`; they ride
  # along into the `try` so the rewrite compiles. A `cond` whose only invalid
  # options are `after`/`else` is left alone — this rule only claims the
  # `:rescue`/`:catch` diagnostics.
  defp extract_bad_opts(opts) do
    Enum.split_with(opts, fn
      {{:__block__, _, [key]}, _} when key in [:rescue, :catch, :after, :else] -> true
      _ -> false
    end)
  end

  defp trigger_opt?({{:__block__, _, [key]}, _}) when key in [:rescue, :catch], do: true
  defp trigger_opt?(_), do: false

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
