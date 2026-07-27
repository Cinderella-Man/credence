defmodule Credence.Semantic.NoRawSendInGenserverHandleCall do
  @moduledoc """
  Fixes `send/2` used to deliver replies from a spawned process inside a
  `handle_call/3` callback, where the `from` argument is a bare tuple
  without an `= from` binding.

  LLMs frequently spawn a process inside `handle_call` and call
  `send(caller_pid, result)` instead of `GenServer.reply(from, result)`,
  causing callers to timeout because the GenServer never sends a reply
  through its protocol.

  Unlike `NoGenserverReplyInHandleCall` (which handles the case where `from`
  is already bound as `{caller_pid, _ref} = _from`), this rule handles the
  case where the `from` argument is a bare tuple `{caller_pid, _}`.

  The fix adds `= from` to the tuple pattern and replaces
  `send(caller_pid, result)` with `GenServer.reply(from, result)`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "send/2 spawned from handle_call/3 — use GenServer.reply/2 instead"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    msg == @match_msg
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_raw_send_in_genserver_handle_call,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        patches = collect_patches(ast)

        case patches do
          [] -> source
          patches -> Sourceror.patch_string(source, patches)
        end

      _ ->
        source
    end
  end

  defp collect_patches(ast) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn
        {:def, _, [{:handle_call, _, [_, from_arg, _]}, kw_list]} = node, acc
        when is_list(kw_list) ->
          p = handle_call_patches(from_arg, kw_list)
          {node, acc ++ p}

        node, acc ->
          {node, acc}
      end)

    patches
  end

  defp handle_call_patches(from_arg, kw_list) do
    with {:ok, var_name} <- extract_bare_tuple_var(from_arg),
         {:ok, _do_key, body} <- find_do_block(kw_list),
         {:ok, send_node} <- find_send_in_spawn(body, var_name),
         %Sourceror.Range{} = send_range <- Sourceror.get_range(send_node),
         %Sourceror.Range{} = from_range <- Sourceror.get_range(from_arg) do
      [_pid, arg] = elem(send_node, 2)
      arg_str = Macro.to_string(arg)
      send_change = "GenServer.reply(from, #{arg_str})"
      from_text = Macro.to_string(from_arg)

      [
        %{range: send_range, change: send_change},
        %{range: from_range, change: "#{from_text} = from"}
      ]
    else
      _ -> []
    end
  end

  # Extract variable name from a bare tuple pattern like {caller_pid, _}
  # (without an = from binding). Rejects {_, _} where both are wildcards.
  defp extract_bare_tuple_var({:__block__, _, [tuple]})
       when is_tuple(tuple) and tuple_size(tuple) == 2 do
    case tuple do
      {{first, _, nil}, {_, _, nil}} when is_atom(first) and first != :_ ->
        {:ok, first}

      {{_, _, nil}, {second, _, nil}} when is_atom(second) and second != :_ ->
        {:ok, second}

      _ ->
        :error
    end
  end

  defp extract_bare_tuple_var(_), do: :error

  defp find_do_block(kw_list) do
    case Enum.find(kw_list, fn
           {{:__block__, _, [:do]}, _} -> true
           _ -> false
         end) do
      {{:__block__, _, [:do]} = key, body} -> {:ok, key, body}
      _ -> :error
    end
  end

  # Find send(var_name, ...) inside a spawned block (spawn/spawn_link/
  # spawn_monitor or Task.async/Task.start/Task.start_link).
  defp find_send_in_spawn(body, var_name) do
    case Macro.prewalk(body, nil, fn
           # Match spawn/spawn_link/spawn_monitor(fn -> ... end)
           {spawn_fn, _, [{:fn, _, clauses}]} = node, nil
           when spawn_fn in [:spawn, :spawn_link, :spawn_monitor] ->
             case find_send_in_fn(clauses, var_name) do
               {:ok, send_node} -> {node, {:found, send_node}}
               :error -> {node, nil}
             end

           # Match Task.async/Task.start/Task.start_link(fn -> ... end)
           {{:., _, [{:__aliases__, _, [:Task]}, fun]}, _, [{:fn, _, clauses}]} = node, nil
           when fun in [:async, :start, :start_link] ->
             case find_send_in_fn(clauses, var_name) do
               {:ok, send_node} -> {node, {:found, send_node}}
               :error -> {node, nil}
             end

           node, acc ->
             {node, acc}
         end) do
      {_, {:found, send_node}} -> {:ok, send_node}
      _ -> :error
    end
  end

  defp find_send_in_fn(clauses, var_name) do
    Enum.reduce_while(clauses, :error, fn
      {:->, _, [[], body]}, _acc ->
        case find_send_to_var(body, var_name) do
          {:ok, send_node} -> {:halt, {:ok, send_node}}
          :error -> {:cont, :error}
        end

      _, _acc ->
        {:cont, :error}
    end)
  end

  defp find_send_to_var(body, var_name) do
    case Macro.prewalk(body, nil, fn
           {:send, _, [{^var_name, _, nil}, _arg]} = node, nil ->
             {node, {:found, node}}

           node, acc ->
             {node, acc}
         end) do
      {_, {:found, node}} -> {:ok, node}
      _ -> :error
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
