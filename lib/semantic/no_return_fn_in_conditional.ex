defmodule Credence.Semantic.NoReturnFnInConditional do
  @moduledoc """
  Fixes chained Python-style `unless cond do return value end` guard patterns
  that cause `undefined function return/1` compiler errors.

  LLMs frequently write sequential validation guards:

      unless type in @types do
        return {:error, :invalid_type}
      end

      unless is_integer(value) and value >= 0 do
        return {:error, :invalid_value}
      end

      {:ok, attrs}

  Since `return/1` does not exist in Elixir, this fails to compile. The fix
  restructures consecutive `unless/return` guards into nested `if/else` chains:

      if type not in @types do
        {:error, :invalid_type}
      else
        unless is_integer(value) and value >= 0 do
          {:error, :invalid_value}
        else
          {:ok, attrs}
        end
      end

  The first `unless` is converted to `if not(cond)`; subsequent guards keep
  their `unless` form but gain an `else` branch carrying the downstream code.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "undefined function return/"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_return_fn_in_conditional,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      result =
        Macro.prewalk(ast, fn
          {kind, meta, [fn_head, body_kw]} = node when kind in [:def, :defp] ->
            case transform_def_body(body_kw) do
              {:ok, new_body_kw} -> {kind, meta, [fn_head, new_body_kw]}
              :error -> node
            end

          node ->
            node
        end)

      if result == ast do
        source
      else
        Sourceror.to_string(result)
      end
    else
      _ -> source
    end
  end

  # The def body keyword list: [{{:__block__, _, [:do]}, body}]
  defp transform_def_body([{{:__block__, do_meta, [:do]}, body}]) do
    {pairs, prefix, final} = collect_unless_returns(body)

    case {pairs, final} do
      {[], _} ->
        :error

      {_, nil} ->
        # No final expression after the guards — leave unchanged
        :error

      _ ->
        chain = build_guard_chain(pairs, final)

        new_body =
          case prefix do
            [] -> chain
            _ -> {:__block__, [], prefix ++ [chain]}
          end

        {:ok, [{{:__block__, do_meta, [:do]}, new_body}]}
    end
  end

  defp transform_def_body(_), do: :error

  # Collect consecutive unless/return pairs from a block body.
  # Returns {[{condition, value} | ...], prefix_stmts, final_expression}.
  defp collect_unless_returns({:__block__, _meta, stmts}) do
    collect_from_list(stmts)
  end

  defp collect_unless_returns(single) do
    case extract_unless_return(single) do
      {:ok, cond, val} -> {[{cond, val}], [], nil}
      :error -> {[], [], nil}
    end
  end

  defp collect_from_list(stmts) do
    # Walk backwards from the end: the final expression is last,
    # consecutive unless/return guards precede it.
    case Enum.reverse(stmts) do
      [final | rest_reversed] ->
        {guard_stmts, prefix} =
          Enum.split_while(rest_reversed, fn stmt ->
            match?({:ok, _, _}, extract_unless_return(stmt))
          end)

        pairs =
          Enum.map(Enum.reverse(guard_stmts), fn stmt ->
            {:ok, cond, val} = extract_unless_return(stmt)
            {cond, val}
          end)

        {pairs, Enum.reverse(prefix), final}

      [] ->
        {[], [], nil}
    end
  end

  # Match: unless cond do return value end
  defp extract_unless_return({:unless, _meta, [condition, [{{:__block__, _, [:do]}, body}]]}) do
    case body do
      {:return, _, [value]} -> {:ok, condition, value}
      _ -> :error
    end
  end

  defp extract_unless_return(_), do: :error

  # Build nested if/else chain from guard pairs.
  # First pair → if not(cond) do value else <rest> end
  # Subsequent pairs → unless cond do value else <rest> end
  defp build_guard_chain([{first_cond, first_val} | rest_pairs], final) do
    inner = build_unless_chain(rest_pairs, final)

    {:if,
     [
       trailing_comments: [],
       leading_comments: [],
       do: [line: 1, column: 1]
     ],
     [
       {:not, [trailing_comments: [], leading_comments: []], [first_cond]},
       [
         {{:__block__, [trailing_comments: [], leading_comments: []], [:do]},
          first_val},
         {{:__block__, [trailing_comments: [], leading_comments: []], [:else]},
          inner}
       ]
     ]}
  end

  defp build_unless_chain([], final), do: final

  defp build_unless_chain([{cond, val} | rest], final) do
    inner = build_unless_chain(rest, final)

    {:unless,
     [
       trailing_comments: [],
       leading_comments: [],
       do: [line: 1, column: 1]
     ],
     [
       cond,
       [
         {{:__block__, [trailing_comments: [], leading_comments: []], [:do]},
          val},
         {{:__block__, [trailing_comments: [], leading_comments: []], [:else]},
          inner}
       ]
     ]}
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
