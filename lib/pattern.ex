defmodule Credence.Pattern do
  @moduledoc """
  Pattern phase — detects and fixes anti-patterns in Elixir code.

  Delegates to the 80+ rules implementing `Credence.Pattern.Rule` behaviour.
  Rules are discovered automatically and run in priority order (lower first),
  with module name as tiebreaker for determinism.
  """

  @spec analyze(String.t(), keyword()) :: [Credence.Issue.t()]
  def analyze(code_string, opts \\ []) do
    opts = Keyword.put_new(opts, :source, code_string)

    case Code.string_to_quoted(code_string) do
      {:ok, ast} ->
        Enum.flat_map(rules(opts), & &1.check(ast, opts))

      {:error, {line, error_msg, token}} ->
        [parse_error_issue(line, error_msg, token)]
    end
  end

  @spec fix(String.t(), keyword()) :: String.t()
  def fix(code_string, opts \\ []) do
    all_rules = rules(opts)
    {fixable, _unfixable} = Enum.split_with(all_rules, & &1.fixable?())

    Enum.reduce(fixable, code_string, fn rule, source ->
      rule.fix(source, opts)
    end)
  end

  defp rules(opts) do
    Keyword.get(opts, :rules, default_rules())
  end

  @doc false
  def default_rules do
    Application.spec(:credence, :modules)
    |> Enum.filter(&implements?(&1, Credence.Pattern.Rule))
    |> Enum.sort_by(&{&1.priority(), &1})
  end

  defp implements?(module, behaviour) do
    behaviour in Keyword.get(module.__info__(:attributes), :behaviour, [])
  end

  defp parse_error_issue(line, error_msg, token) do
    %Credence.Issue{
      rule: :parse_error,
      message: "Syntax error: #{error_msg} at token #{inspect(token)}",
      meta: %{line: line}
    }
  end
end
