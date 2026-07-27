defmodule Credence.Semantic.NoHallucinatedErlangWarn do
  @moduledoc """
  Fixes the compile error caused by calling `:erlang.warn/1`.

  LLMs frequently hallucinate `:erlang.warn/1` as the warning/logging
  function; it does not exist in OTP. The compiler emits:

      ":erlang.warn/1 is undefined or private"

  The idiomatic Elixir replacement is `Logger.warning/1`. This targeted
  semantic rule detects `:erlang.warn(args)` calls and rewrites them to
  `Logger.warning(args)`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg ":erlang.warn/"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg) and String.contains?(msg, "is undefined or private")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_hallucinated_erlang_warn,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {{:., dot_meta, [{:__block__, block_meta, [:erlang]}, :warn]}, call_meta, args}, _acc
          when is_list(args) ->
            alias_meta = Keyword.put(block_meta, :last, block_meta[:line] || dot_meta[:line])
            new_dot = {{:., dot_meta, [{:__aliases__, alias_meta, [:Logger]}, :warning]}, call_meta, args}
            {new_dot, true}

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
