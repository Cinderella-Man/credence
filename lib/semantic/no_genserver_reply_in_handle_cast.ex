defmodule Credence.Semantic.NoGenserverReplyInHandleCast do
  @moduledoc """
  Fixes `GenServer.reply/2` called inside a `handle_cast/2` callback.

  LLMs frequently extract a `caller` PID from the cast message and call
  `GenServer.reply(caller, msg)` inside `handle_cast/2`. But
  `GenServer.reply/2` expects a `{pid, tag}` from-tuple that `GenServer`
  built when dispatching a `handle_call/3` — a bare PID always raises
  `FunctionClauseError` at runtime. The fix replaces every
  `GenServer.reply(caller, msg)` inside `handle_cast` with `send(caller, msg)`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "GenServer.reply/2 called inside handle_cast/2"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_genserver_reply_in_handle_cast,
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
            {:def, meta, [{:handle_cast, _, _} = head, kw_list]} = node, _acc
            when is_list(kw_list) ->
              case do_fix_handle_cast_body(kw_list) do
                {:ok, new_kw} -> {{:def, meta, [head, new_kw]}, true}
                :error -> {node, false}
              end

            node, acc ->
              {node, acc}
          end)

        if changed?, do: Sourceror.to_string(new_ast), else: source

      _ ->
        source
    end
  end

  # Walk the do-block inside a handle_cast and replace every
  # GenServer.reply(x, y) call with send(x, y).
  defp do_fix_handle_cast_body(kw_list) do
    case find_do_block(kw_list) do
      {:ok, do_key, body} ->
        {new_body, changed?} = replace_reply_with_send(body)

        if changed? do
          {:ok, replace_do_block(kw_list, do_key, new_body)}
        else
          :error
        end

      :error ->
        :error
    end
  end

  defp find_do_block(kw_list) do
    case Enum.find(kw_list, fn
           {{:__block__, _, [:do]}, _} -> true
           _ -> false
         end) do
      {{:__block__, _, [:do]} = key, body} -> {:ok, key, body}
      _ -> :error
    end
  end

  defp replace_do_block(kw_list, do_key, new_body) do
    Enum.map(kw_list, fn
      {^do_key, _} -> {do_key, new_body}
      other -> other
    end)
  end

  # Replace GenServer.reply(a, b) with send(a, b) inside an AST subtree.
  defp replace_reply_with_send(ast) do
    Macro.prewalk(ast, false, fn
      {{:., dot_meta, [{:__aliases__, alias_meta, [:GenServer]}, :reply]}, call_meta, args},
      _acc
      when is_list(args) and length(args) == 2 ->
        new_node = {:send, call_meta, args}
        # Preserve leading/trailing comments from the original node
        new_node = copy_comments({{:., dot_meta, [{:__aliases__, alias_meta, [:GenServer]}, :reply]}, call_meta, args}, new_node)
        {new_node, true}

      node, acc ->
        {node, acc}
    end)
  end

  defp copy_comments(src, dst) do
    leading = get_in(elem(src, 1), [:leading_comments]) || []
    trailing = get_in(elem(src, 1), [:trailing_comments]) || []

    if leading == [] and trailing == [] do
      dst
    else
      dst_meta =
        elem(dst, 1)
        |> Keyword.update(:leading_comments, leading, &(leading ++ &1))
        |> Keyword.update(:trailing_comments, trailing, &(&1 ++ trailing))

      put_elem(dst, 1, dst_meta)
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
