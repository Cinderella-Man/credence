defmodule Credence.Semantic.NoUsePlugConn do
  @moduledoc """
  Fixes the compile error caused by `use Plug.Conn`.

  LLMs repeatedly write `use Plug.Conn` (confusing it with `use Plug.Router`),
  which fails to compile because `Plug.Conn.__using__/1` is undefined; the
  correct form is `import Plug.Conn`.

  The compiler emits:

      function Plug.Conn.__using__/1 is undefined or private

  ## Auto-fix

  Replaces `use Plug.Conn` with `import Plug.Conn`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "function Plug.Conn.__using__/1 is undefined or private"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_use_plug_conn,
      message: "Use `import Plug.Conn` instead of `use Plug.Conn`.",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    String.replace(source, "use Plug.Conn", "import Plug.Conn")
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
