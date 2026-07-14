defmodule Credence.Semantic.NoRaiseInHandleCall do
  @moduledoc """
  Fixes GenServer `handle_call` callbacks that raise exceptions.

  LLMs repeatedly `raise` inside `handle_call` (3/3 attempts on common rows),
  crashing the GenServer process instead of returning an error to the caller.
  The existing `no_genserver_cast_with_raise` covers `handle_cast` but not
  `handle_call`, leaving this common anti-pattern unpatched.

  The fix rewrites `raise SomeException, msg` inside a `handle_call` clause
  to `{:reply, {:error, msg}, state}`, propagating the error as a value the
  caller can handle.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "raise in handle_call — use {:reply, {:error, msg}, state} instead"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    msg == @match_msg
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_raise_in_handle_call,
      message: @match_msg,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        new_ast = transform_handle_calls(ast)

        if new_ast != ast do
          Sourceror.to_string(new_ast)
        else
          source
        end

      _ ->
        source
    end
  end

  # ---------------------------------------------------------------------------
  # Transformation: raise → {:reply, {:error, msg}, state} in handle_call
  # ---------------------------------------------------------------------------

  defp transform_handle_calls(ast) do
    Macro.prewalk(ast, fn
      {:def, def_meta, [{:handle_call, hc_meta, args}, kw_body]} = node
      when is_list(kw_body) and length(args) >= 3 ->
        state_arg = Enum.at(args, 2)
        state_name = extract_var_name(state_arg)

        if state_name != nil and kw_has_raise?(kw_body) do
          new_kw = replace_raises_in_body(kw_body, state_name)
          {:def, def_meta, [{:handle_call, hc_meta, args}, new_kw]}
        else
          node
        end

      node ->
        node
    end)
  end

  # Check if a keyword do-block body contains a `raise`.
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

  # Replace every `raise` with {:reply, {:error, msg}, state_var} in the body.
  defp replace_raises_in_body(kw_body, state_name) do
    Enum.map(kw_body, fn
      {{:__block__, do_meta, [:do]}, body} ->
        new_body =
          Macro.prewalk(body, fn
            {:raise, raise_meta, args} ->
              msg_expr = extract_raise_message(args)
              build_reply_error_tuple(raise_meta, msg_expr, state_name)

            node ->
              node
          end)

        {{:__block__, do_meta, [:do]}, new_body}

      other ->
        other
    end)
  end

  # Extract the message expression from a `raise` call's arguments.
  # raise ArgumentError, msg  → args = [ArgumentError, msg] → msg
  # raise "msg"               → args = ["msg"]             → "msg"
  defp extract_raise_message([_exception, msg]), do: msg
  defp extract_raise_message([msg]), do: msg
  defp extract_raise_message(_), do: {:__block__, [], ["unknown error"]}

  # Build {:reply, {:error, msg_expr}, state_var} AST.
  defp build_reply_error_tuple(meta, msg_expr, state_name) do
    line = Keyword.get(meta, :line)
    col = Keyword.get(meta, :column)

    reply_meta =
      [line: line, column: col] ++
        (if col, do: [closing: [line: line, column: col + 8]], else: [])

    {:{}, reply_meta,
     [
       {:__block__, [], [:reply]},
       {:{}, [],
        [
          {:__block__, [], [:error]},
          msg_expr
        ]},
       {state_name, [], nil}
     ]}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Extract a variable name from an AST node (e.g. from a function arg).
  defp extract_var_name({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: name
  defp extract_var_name(_), do: nil

  defp find_do_block(kw_list) do
    Enum.find_value(kw_list, :error, fn
      {{:__block__, _, [:do]}, body} -> {:ok, body}
      _ -> nil
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
