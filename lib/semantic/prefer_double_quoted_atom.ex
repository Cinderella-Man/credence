defmodule Credence.Semantic.PreferDoubleQuotedAtom do
  @moduledoc """
  Repairs the deprecation warning for single-quoted atom literals.

  Elixir deprecates `:'atom_name'` syntax (single-quoted atoms) in favour
  of the double-quoted `:"atom_name"` form.  Under `--warnings-as-errors`
  this becomes a compile failure.  The compiler emits:

      using single-quoted strings to represent charlists is deprecated.

  The fix is a deterministic source-level rewrite: replace `:'...'` with
  `:"..."` everywhere in the source.  Semantics are identical — both forms
  produce the same atom value.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "using single-quoted strings to represent charlists is deprecated"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :prefer_double_quoted_atom,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    # Replace `:'...'` with `:"..."`.
    # The `:` prefix distinguishes atoms from standalone charlists.
    # `[^']` matches any char except single-quote (no escaped-quote support
    # needed — Elixir atoms with internal quotes are vanishingly rare).
    Regex.replace(~r/:'([^']*)'/, source, ":\"\\1\"")
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
