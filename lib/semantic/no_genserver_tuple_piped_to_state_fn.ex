defmodule Credence.Semantic.NoGenserverTuplePipedToStateFn do
  @moduledoc """
  Fixes GenServer callbacks that pipe `{:noreply, state}` or `{:reply, reply, state}`
  into a helper function expecting a bare state map.

  LLMs frequently write:

      {:noreply, %{state | count: state.count + 1}}
      |> maybe_process()

  which passes the full tuple to `maybe_process/1` instead of the bare state map,
  causing a `BadMapError` at runtime. The fix moves the helper call inside the tuple:

      {:noreply, maybe_process(%{state | count: state.count + 1})}
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "GenServer reply tuple piped into helper function"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_genserver_tuple_piped_to_state_fn,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {new_ast, changed?} =
          Macro.prewalk(ast, false, fn
            {:|>, _pipe_meta, [left, right]} = node, acc ->
              case transform_pipe(left, right) do
                {:ok, result} -> {result, true}
                :error -> {node, acc}
              end

            node, acc ->
              {node, acc}
          end)

        if changed?, do: Sourceror.to_string(new_ast), else: source

      _ ->
        source
    end
  end

  defp transform_pipe(left, right) do
    with {:ok, block_meta, tag, tag_meta, elements} <- unwrap_tuple(left),
         {:ok, fn_name, fn_meta, fn_args} <- unwrap_fn_call(right) do
      state = List.last(elements)
      new_fn = {fn_name, fn_meta, [state | fn_args]}
      new_elements = List.replace_at(elements, -1, new_fn)
      new_tuple = rebuild_tuple(tag, tag_meta, new_elements)
      {:ok, {:__block__, block_meta, [new_tuple]}}
    else
      _ -> :error
    end
  end

  defp unwrap_tuple({:__block__, meta, [tuple]}) do
    case unwrap_tuple_inner(tuple) do
      {:ok, tag, tag_meta, elements} -> {:ok, meta, tag, tag_meta, elements}
      :error -> :error
    end
  end

  defp unwrap_tuple(tuple) do
    case unwrap_tuple_inner(tuple) do
      {:ok, tag, tag_meta, elements} -> {:ok, [], tag, tag_meta, elements}
      :error -> :error
    end
  end

  # {:noreply, state} — 2-tuple
  defp unwrap_tuple_inner({{:__block__, meta, [:noreply]}, state}) do
    {:ok, :noreply, meta, [state]}
  end

  # {:reply, reply, state} — 3-tuple
  defp unwrap_tuple_inner({:{}, _meta, [{:__block__, tag_meta, [:reply]}, reply, state]}) do
    {:ok, :reply, tag_meta, [reply, state]}
  end

  defp unwrap_tuple_inner(_), do: :error

  defp unwrap_fn_call({name, meta, args}) when is_atom(name) and is_list(args) do
    {:ok, name, meta, args}
  end

  defp unwrap_fn_call(_), do: :error

  defp rebuild_tuple(:noreply, tag_meta, [new_state]) do
    {{:__block__, tag_meta, [:noreply]}, new_state}
  end

  defp rebuild_tuple(:reply, tag_meta, [reply, new_state]) do
    {:{}, [], [{:__block__, tag_meta, [:reply]}, reply, new_state]}
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
