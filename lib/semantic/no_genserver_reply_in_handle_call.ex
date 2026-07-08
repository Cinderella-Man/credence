defmodule Credence.Semantic.NoGenserverReplyInHandleCall do
  @moduledoc """
  Fixes `send/2` used to deliver replies from a `handle_call/3` callback.

  LLMs repeatedly use `send(caller_pid, result)` inside tasks spawned from
  `handle_call` instead of `GenServer.reply(from, result)`, causing callers to
  timeout. The existing `no_genserver_reply_in_handle_cast` covers `handle_cast`
  but misses `handle_call` with `{:noreply, state}`.

  The fix rewrites `send(caller_pid, result)` to `GenServer.reply(from, result)`
  and updates the `from` parameter binding from `{caller_pid, _ref} = _from` to
  `{_, _} = from`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "send/2 used to reply from handle_call/3 — use GenServer.reply/2 instead"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    msg == @match_msg
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_genserver_reply_in_handle_call,
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
    with {:ok, var_name} <- extract_tuple_var(from_arg),
         {:ok, _do_key, body} <- find_do_block(kw_list),
         {:ok, send_node} <- find_send_to_var(body, var_name),
         %Sourceror.Range{} = send_range <- Sourceror.get_range(send_node),
         %Sourceror.Range{} = from_range <- Sourceror.get_range(from_arg) do
      [_pid, arg] = elem(send_node, 2)
      arg_str = Macro.to_string(arg)
      send_change = "GenServer.reply(from, #{arg_str})"

      [
        %{range: send_range, change: send_change},
        %{range: from_range, change: "{_, _} = from"}
      ]
    else
      _ -> []
    end
  end

  # Extract the first variable name from a tuple destructure binding like
  # `{caller_pid, _ref} = _from`. Returns {:ok, :caller_pid} or :error.
  defp extract_tuple_var({:=, _, [{:__block__, _, [tuple]}, {var_name, _, nil}]})
       when is_atom(var_name) and is_tuple(tuple) do
    case tuple do
      {{first, _, nil}, _} when is_atom(first) -> {:ok, first}
      {_, {second, _, nil}} when is_atom(second) -> {:ok, second}
      _ -> :error
    end
  end

  defp extract_tuple_var(_), do: :error

  defp find_do_block(kw_list) do
    case Enum.find(kw_list, fn
           {{:__block__, _, [:do]}, _} -> true
           _ -> false
         end) do
      {{:__block__, _, [:do]} = key, body} -> {:ok, key, body}
      _ -> :error
    end
  end

  # Find a send(var_name, ...) call in the AST body.
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
