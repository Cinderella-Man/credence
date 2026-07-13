defmodule Credence.Semantic.NoBareFunctionDefSyntax do
  @moduledoc """
  Fixes bare function definitions missing the `def` keyword.

  LLMs frequently emit bare `init(opts) do … end` (missing `def`) when
  writing Plug.Router modules. This causes an "undefined function init/2"
  compile error because Elixir parses it as a local function call.

  The fix is deterministic: when the compiler reports `undefined function
  <name>/<arity>` and the diagnostic line contains `<name>(args) do`,
  prepend `def ` to that line.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @undefined_fn_re ~r/^undefined function (\w+)\/\d+/

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    Regex.match?(@undefined_fn_re, msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_bare_function_def_syntax,
      message: "Bare function definition missing `def` keyword: #{diagnostic.message}",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    case extract_fn_name(diagnostic.message) do
      nil ->
        source

      fn_name ->
        target = line(diagnostic)
        lines = String.split(source, "\n")

        case Enum.at(lines, target - 1) do
          nil ->
            source

          src_line ->
            # Only fix lines that match `<name>(...) do` — a bare function
            # definition missing the `def` keyword.
            bare_re = ~r/^(\s*)#{Regex.escape(fn_name)}\(.*\)\s+do\s*$/

            if Regex.match?(bare_re, src_line) do
              # Prepend `def ` after leading whitespace, preserving indentation
              fixed_line =
                Regex.replace(~r/^(\s*)/, src_line, "\\1def ", global: false)

              lines
              |> List.replace_at(target - 1, fixed_line)
              |> Enum.join("\n")
            else
              source
            end
        end
    end
  end

  defp extract_fn_name(message) do
    case Regex.run(@undefined_fn_re, message) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
