defmodule Credence.Semantic.NoSendToFromInHandleCall do
  @moduledoc """
  Fixes `send(from, msg)` in GenServer callbacks where `from` is the
  `handle_call` reply reference.

  Since OTP 26, `from` is `{pid, [:alias | ref]}` which makes `send/2` raise
  `ArgumentError: invalid destination` at runtime. `GenServer.reply/2` always
  works regardless of the OTP version.

  The fix replaces `send(from, msg)` with `GenServer.reply(from, msg)`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "send/2 called with handle_call from — use GenServer.reply/2 instead"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    msg == @match_msg
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_send_to_from_in_handle_call,
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
        {:send, _meta, [{:from, _, nil}, arg]} = node, acc ->
          case Sourceror.get_range(node) do
            %Sourceror.Range{} = range ->
              arg_str = Macro.to_string(arg)
              change = "GenServer.reply(from, #{arg_str})"
              {node, acc ++ [%{range: range, change: change}]}

            _ ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    patches
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
