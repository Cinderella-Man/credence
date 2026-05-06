defmodule Credence.Pattern do
  @moduledoc """
  Pattern-level analysis and auto-fixing.

  This is the core of Credence — the 80+ rules that detect and fix
  anti-patterns in LLM-generated Elixir code. Rules use `Macro.prewalk/3`
  for detection and either AST transformation or line-level regex for fixes.

  Rules are discovered automatically from modules implementing the
  `Credence.Rule` behaviour.
  """
  alias Credence.Issue

  @doc """
  Analyzes parseable code with all semantic rules.
  Returns a list of issues found.
  """
  @spec analyze(String.t(), keyword()) :: [Issue.t()]
  def analyze(code_string, opts \\ []) do
    rules = Keyword.get(opts, :rules, default_rules())
    opts = Keyword.put_new(opts, :source, code_string)

    case Code.string_to_quoted(code_string) do
      {:ok, ast} ->
        run_rules(ast, rules, opts)

      {:error, {line, error_msg, token}} ->
        [parse_error_issue(line, error_msg, token)]
    end
  end

  @doc """
  Auto-fixes all fixable issues. Returns the fixed source string.

  Pipes the source through each fixable rule's `fix/2` in alphabetical
  order (by module name). Rules that implement `fixable?/0 -> true`
  are included.
  """
  @spec fix(String.t(), keyword()) :: String.t()
  def fix(code_string, opts \\ []) do
    rules = Keyword.get(opts, :rules, default_rules())
    {fixable, _unfixable} = Enum.split_with(rules, & &1.fixable?())

    Enum.reduce(fixable, code_string, fn rule, source ->
      rule.fix(source, opts)
    end)
  end

  # ── Private ─────────────────────────────────────────────────────

  defp run_rules(ast, rules, opts) do
    Enum.flat_map(rules, & &1.check(ast, opts))
  end

  @doc false
  def default_rules do
    Application.spec(:credence, :modules)
    |> Enum.filter(fn module ->
      Credence.Rule in Keyword.get(module.__info__(:attributes), :behaviour, [])
    end)
  end

  defp parse_error_issue(line, error_msg, token) do
    %Issue{
      rule: :parse_error,
      message: "Syntax error: #{error_msg} at token #{inspect(token)}",
      meta: %{line: line}
    }
  end
end
