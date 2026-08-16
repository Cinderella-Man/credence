defmodule Credence.Semantic.NoUsePlugConn do
  @moduledoc """
  Fixes the compile error caused by `use Plug.Conn`.

  LLMs repeatedly write `use Plug.Conn` (confusing it with `use Plug.Router`),
  which fails to compile because `Plug.Conn.__using__/1` is undefined; the
  correct form is `import Plug.Conn`.

  The compiler raises, and the semantic round turns the exception into an
  error diagnostic:

      function Plug.Conn.__using__/1 is undefined or private

  ## Auto-fix

  Rewrites `use Plug.Conn` to `import Plug.Conn`.

  The exception carries no line, so the diagnostic's position is `0` and the
  rewrite cannot be aimed by position. It is aimed by the AST instead: the
  source is parsed, and only a line that holds a real `use Plug.Conn` *call*
  (a bare `use` with `Plug.Conn` as its single argument) is touched — and even
  then only when that line reads exactly `use Plug.Conn`, optionally followed
  by a comment. Everything else in the file is left byte-identical.

  Declined on purpose (no issue reported, no rewrite):

    * `use Plug.ConnTest`, `use Plug.Conn.Status`, `use MyApp.Plug.Conn` — a
      different module, so a plain string replace would corrupt them;
    * the text `use Plug.Conn` inside a string, heredoc or comment — it is not
      a `use` call, so the AST walk never sees it;
    * `use Plug.Conn, some: :option` — `import` does not take arbitrary
      options, so there is no same-meaning rewrite;
    * `use(Plug.Conn)`, `use Plug.Conn` split over two lines, or a `use` that
      does not start its line — the line does not read as a plain
      `use Plug.Conn`;
    * `alias Plug.Conn` + `use Conn` — the alias in the AST is not
      `Plug.Conn`.

  `should_report?/2` re-runs `fix/2`, so a diagnostic the rewrite declines is
  never reported as an issue either — the check and the fix always agree.

  ## Bad

      defmodule MyApp.Plug.Greeter do
        use Plug.Conn

        def call(conn, _opts) do
          send_resp(conn, 200, "ok")
        end
      end

  ## Good

      defmodule MyApp.Plug.Greeter do
        import Plug.Conn

        def call(conn, _opts) do
          send_resp(conn, 200, "ok")
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "function Plug.Conn.__using__/1 is undefined or private"

  # A line whose whole content is `use Plug.Conn` (plus optional comment).
  @use_line ~r/^([ \t]*)use([ \t]+Plug\.Conn)([ \t]*(?:#.*)?)$/

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.starts_with?(msg, @match_msg)
  end

  def match?(_), do: false

  @doc """
  Only report a diagnostic this rule can actually rewrite: the decision is made
  by re-running the rewrite, so a shape the fix leaves alone never becomes an
  issue.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

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
    case use_plug_conn_lines(source) do
      [] ->
        source

      lines ->
        source
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.map_join("\n", fn {text, index} ->
          if index in lines, do: rewrite_line(text), else: text
        end)
    end
  end

  defp rewrite_line(text), do: Regex.replace(@use_line, text, "\\1import\\2\\3")

  # Lines that hold a `use Plug.Conn` call with `Plug.Conn` as its only
  # argument. Unparseable source yields none, so the fix is a no-op.
  defp use_plug_conn_lines(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {_ast, lines} =
          Macro.prewalk(ast, [], fn
            {:use, meta, [{:__aliases__, _, [:Plug, :Conn]}]} = node, acc ->
              {node, add_line(acc, meta[:line])}

            node, acc ->
              {node, acc}
          end)

        lines

      {:error, _} ->
        []
    end
  end

  defp add_line(acc, line) when is_integer(line), do: [line | acc]
  defp add_line(acc, _line), do: acc

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
  defp line(_), do: 0
end
