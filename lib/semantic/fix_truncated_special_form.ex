defmodule Credence.Semantic.FixTruncatedSpecialForm do
  @moduledoc """
  Fixes truncated Elixir special-form references (`__MODULE`, `__ENV`, `__DIR`,
  `__CALLER`, `__STACKTRACE`) that are missing the trailing `__`.

  LLMs frequently produce `__MODULE` (single trailing underscore — or none at
  all) instead of `__MODULE__`.  The compiler treats the truncated form as a
  regular (undefined) variable and emits:

      undefined variable "__MODULE"

  This rule matches that diagnostic for any of the five `__X__` special forms
  and deterministically appends the missing underscores in the source text.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @dunder_names ~w(__MODULE __ENV __DIR __CALLER __STACKTRACE)

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    case Regex.run(~r/^undefined variable "(__[A-Z_]+)"$/, msg) do
      [_, name] -> name in @dunder_names
      _ -> false
    end
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_truncated_special_form,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    case Regex.run(~r/^undefined variable "(__[A-Z_]+)"$/, msg) do
      [_, target] when target in @dunder_names ->
        # Replace the truncated form — only when NOT already followed by `_`
        # (which would indicate the correct `__MODULE__` form).
        {:ok, pattern} = Regex.compile("#{Regex.escape(target)}(?!_)")
        Regex.replace(pattern, source, "#{target}__")

      _ ->
        source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
