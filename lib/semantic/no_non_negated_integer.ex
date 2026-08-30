defmodule Credence.Semantic.NoNonNegatedInteger do
  @moduledoc """
  Fixes compiler errors about the undefined type `non_negated_integer/0`.

  LLMs commonly produce `non_negated_integer()` in typespecs when they mean
  `non_neg_integer()`.  The Elixir compiler emits:

      type non_negated_integer/0 undefined (no such type in Module)

  The fix is the textual substitution `non_negated_integer` →
  `non_neg_integer` — both types describe the same set of values — but it is
  applied **only on the line the compiler flagged**. That line is a type-only
  context (`@spec`/`@type`/`@callback`/…), so the rename touches a type
  reference and nothing else; a blanket replace across the whole source would
  also rewrite an unrelated string literal, comment, atom or identifier named
  `non_negated_integer` elsewhere in the file, which changes the program's
  answer.

  The rule runs at a lower `priority` than `NoBareNamesInSpec`: that rule's
  `type _/0 undefined` matcher also matches this diagnostic but cannot fix the
  parenthesised type call (`non_negated_integer()`), so this rule must be tried
  first or it would never fire.

  ## Bad

      defmodule SolutionNNNI do
        @spec power_of_num(number(), non_negated_integer()) :: number()
        def power_of_num(_base, 0), do: 1
        def power_of_num(base, e) when is_integer(e) and e > 0, do: base * power_of_num(base, e - 1)
      end

  ## Good

      defmodule SolutionNNNI do
        @spec power_of_num(number(), non_neg_integer()) :: number()
        def power_of_num(_base, 0), do: 1
        def power_of_num(base, e) when is_integer(e) and e > 0, do: base * power_of_num(base, e - 1)
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def priority, do: 400

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, "non_negated_integer") and
      String.contains?(msg, "undefined")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_non_negated_integer,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    case line(diagnostic) do
      line_no when is_integer(line_no) ->
        source
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.map_join("\n", fn
          {text, ^line_no} ->
            String.replace(text, "non_negated_integer", "non_neg_integer")

          {text, _} ->
            text
        end)

      _ ->
        source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
  defp line(_), do: nil
end
