defmodule Credence.Semantic.NoGenserverCastWithRaise do
  @moduledoc """
  Fixes GenServer `handle_cast` callbacks that raise exceptions.

  LLMs commonly use `GenServer.cast` for mutation operations whose handlers
  raise validation errors. Since `cast` is fire-and-forget, exceptions silently
  crash the server while callers get `:ok` — genuinely broken code. Switching
  to `call` propagates errors back to the caller.

  The fix converts `handle_cast` clauses containing `raise` to `handle_call`
  (adding the `_from` parameter and changing `{:noreply, state}` to
  `{:reply, :ok, state}`) and rewrites `GenServer.cast` calls to
  `GenServer.call`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_prefix "got \"@impl true\" for function"
  @match_suffix "but no behaviour was declared"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_prefix) and String.contains?(msg, @match_suffix)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_genserver_cast_with_raise,
      message: "GenServer.cast handler raises — use call to propagate errors",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        if has_handle_cast_with_raise?(ast) do
          ast
          |> transform_casts_and_calls()
          |> Sourceror.to_string()
        else
          source
        end

      _ ->
        source
    end
  end

  # ---------------------------------------------------------------------------
  # Detection: does any handle_cast clause contain a `raise`?
  # ---------------------------------------------------------------------------

  defp has_handle_cast_with_raise?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:def, _, [{:handle_cast, _, _}, kw_body]}, acc ->
          {nil, acc or kw_has_raise?(kw_body)}

        {:def, _, [{:when, _, [{:handle_cast, _, _}, _]}, kw_body]}, acc ->
          {nil, acc or kw_has_raise?(kw_body)}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp kw_has_raise?(kw_body) do
    case find_do_block(kw_body) do
      {:ok, body} -> body_has_raise?(body)
      :error -> false
    end
  end

  defp body_has_raise?(body) do
    {_, found} =
      Macro.prewalk(body, false, fn
        {:raise, _, _} = node, _ -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  # ---------------------------------------------------------------------------
  # Transformation: handle_cast → handle_call, GenServer.cast → .call
  # ---------------------------------------------------------------------------

  defp transform_casts_and_calls(ast) do
    Macro.prewalk(ast, fn
      # handle_cast without guard
      {:def, def_meta, [{:handle_cast, cast_meta, [msg, state]}, kw_body]} = node ->
        if kw_has_raise?(kw_body) do
          new_kw = transform_noreply(kw_body)

          {:def, def_meta,
           [{:handle_call, cast_meta, [msg, {:_from, [], nil}, state]}, new_kw]}
        else
          node
        end

      # handle_cast with guard
      {:def, def_meta, [{:when, when_meta, [{:handle_cast, cast_meta, [msg, state]}, guard]}, kw_body]} = node ->
        if kw_has_raise?(kw_body) do
          new_kw = transform_noreply(kw_body)

          new_head =
            {:when, when_meta,
             [{:handle_call, cast_meta, [msg, {:_from, [], nil}, state]}, guard]}

          {:def, def_meta, [new_head, new_kw]}
        else
          node
        end

      # GenServer.cast → GenServer.call
      {{:., dot_meta, [{:__aliases__, alias_meta, [:GenServer]}, :cast]}, call_meta, args} ->
        {{:., dot_meta, [{:__aliases__, alias_meta, [:GenServer]}, :call]}, call_meta, args}

      node ->
        node
    end)
  end

  # Replace {:noreply, state} with {:reply, :ok, state} in the do-block body.
  defp transform_noreply(kw_body) do
    Enum.map(kw_body, fn
      {{:__block__, do_meta, [:do]}, body} ->
        new_body =
          Macro.prewalk(body, fn
            {{:__block__, meta, [:noreply]}, state_expr} ->
              line = Keyword.get(meta, :line)
              col = Keyword.get(meta, :column)

              {:{},
               [line: line, column: col] ++
                 (if col, do: [closing: [line: line, column: col + 13]], else: []),
               [{:__block__, [], [:reply]}, {:__block__, [], [:ok]}, state_expr]}

            node ->
              node
          end)

        {{:__block__, do_meta, [:do]}, new_body}

      other ->
        other
    end)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp find_do_block(kw_list) do
    Enum.find_value(kw_list, :error, fn
      {{:__block__, _, [:do]}, body} -> {:ok, body}
      _ -> nil
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
