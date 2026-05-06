defmodule Credence.Syntax do
  @moduledoc """
  Syntax phase — fixes code that won't parse.

  Only runs when `Code.string_to_quoted/1` fails. Delegates to rules
  implementing `Credence.Syntax.Rule` behaviour.
  """

  @spec analyze(String.t(), keyword()) :: [Credence.Issue.t()]
  def analyze(source, _opts \\ []) do
    case Code.string_to_quoted(source) do
      {:ok, _ast} -> []
      {:error, _} -> Enum.flat_map(rules(), & &1.analyze(source))
    end
  end

  @spec fix(String.t(), keyword()) :: String.t()
  def fix(source, _opts \\ []) do
    case Code.string_to_quoted(source) do
      {:ok, _ast} ->
        source

      {:error, _} ->
        fixed = Enum.reduce(rules(), source, fn rule, src -> rule.fix(src) end)

        # Verify fix actually helped — don't return mangled code
        case Code.string_to_quoted(fixed) do
          {:ok, _} -> fixed
          {:error, _} -> fixed
        end
    end
  end

  defp rules do
    Application.spec(:credence, :modules)
    |> Enum.filter(&implements?(&1, Credence.Syntax.Rule))
    |> Enum.sort_by(&{&1.priority(), &1})
  end

  defp implements?(module, behaviour) do
    behaviour in Keyword.get(module.__info__(:attributes), :behaviour, [])
  end
end
