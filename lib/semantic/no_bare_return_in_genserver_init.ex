defmodule Credence.Semantic.NoBareReturnInGenserverInit do
  @moduledoc """
  Fixes GenServer `init/1` callbacks that return a bare value instead of
  wrapping it in `{:ok, state}`.

  LLMs frequently return a bare map, struct, list, or other value from
  `init/1` without the required OTP tuple wrapper:

      def init(_opts) do
        %{count: 0}
      end

  Every `GenServer.call/3` then crashes with `{:bad_return_value, ...}`.
  The fix wraps the bare return in `{:ok, ...}`:

      def init(_opts) do
        {:ok, %{count: 0}}
      end

  The rule only fires when the `init/1` body is a single expression that is
  NOT already a valid OTP return (`{:ok, _}`, `{:stop, _}`, `{:ok, _, _}`,
  or `:ignore`).
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "init/1 must return {:ok, state}"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_bare_return_in_genserver_init,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed?} =
        Macro.prewalk(ast, false, fn
          {:def, meta, [{:init, _, _} = head, kw_list]} = node, acc
          when is_list(kw_list) ->
            case do_fix_init_body(kw_list) do
              {:ok, new_kw} -> {{:def, meta, [head, new_kw]}, true}
              :error -> {node, acc}
            end

          node, acc ->
            {node, acc}
        end)

      if changed?, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  defp do_fix_init_body(kw_list) do
    case find_do_block(kw_list) do
      {:ok, do_key, body} ->
        if bare_return?(body) do
          new_body = wrap_in_ok_tuple(body)
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

  # Valid OTP returns — do not wrap these.
  # :ignore
  defp bare_return?({:__block__, _, [:ignore]}), do: false
  # Unwrap single-expression __block__ to inspect the inner expression
  defp bare_return?({:__block__, _, [expr]}), do: bare_return?(expr)
  # {:ok, state}
  defp bare_return?({{:__block__, _, [:ok]}, _}), do: false
  # {:stop, reason}
  defp bare_return?({{:__block__, _, [:stop]}, _}), do: false
  # {:ok, state, timeout/hibernate/continue} (3+ element tuple)
  defp bare_return?({:{}, _, [{:__block__, _, [:ok]} | _]}), do: false
  # Everything else is a bare return
  defp bare_return?(_), do: true

  defp wrap_in_ok_tuple(body) do
    ok_ast = {:__block__, [], [:ok]}
    {:__block__, [], [{ok_ast, body}]}
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
