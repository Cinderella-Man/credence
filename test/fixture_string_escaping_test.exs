defmodule Credence.FixtureStringEscapingTest do
  @moduledoc """
  The gate that keeps every **code fixture** a `\"""` heredoc — never an escaped
  `"...\\n..."` / `"...\\""` string, a `~s`/`~S` sigil, or a `"a" <> "b"`
  concatenation (a common way to sneak a multi-line string past the rule).

  Scoped to **fixture positions** (the code-under-test): a string passed to a rule
  verb (`check`/`fix`/`clean?`/…/`assert_equivalent`), compared to one with `==`,
  or assigned to `code`/`input`/`expected`/`source`/…. Non-fixtures — a `=~`
  message-substring, a `mark_equivalence_*` reason, a `\#{}` fragment in a list —
  are not checked; they legitimately stay plain.

  Introspected with Sourceror (delimiter-aware). A fixture is OK when it's a
  heredoc, a `~S\"""...\"""` sigil-heredoc (also triple quotes, raw for `\#{}` code),
  a *single-line* interpolated string/sigil, or code that contains `\"""` (can't
  nest in a heredoc). A multi-line interpolated string (one with a `\\n` escape) is
  **not** OK — it must heredoc, same as a multi-line plain string. Plus a tiny
  file allow-list for fixtures a heredoc breaks structurally.
  """
  use ExUnit.Case, async: true

  import Credence.MetaTestSupport

  @dirs ["test/pattern", "test/semantic", "test/syntax"]

  @allow %{
    "test/pattern/no_redundant_binary_syntax_fix_test.exs" =>
      "the fix reprints the whole expression, dropping the input's trailing " <>
        "newline; a heredoc expected (which has one) can't match, and the quoted " <>
        "result has no heredoc/sigil-free form",
    "test/semantic/missing_use_exunit_case_fix_test.exs" =>
      "the fix forces a trailing blank line; mix format trims a heredoc's, changing the value"
  }

  defp files do
    @dirs |> Enum.flat_map(&Path.wildcard("#{&1}/**/*_test.exs")) |> Enum.sort()
  end

  # `fixtures/1` and `fixture_ok?/1` live in `Credence.MetaTestSupport`, so the
  # generator pin asserts against the same code this gate enforces.

  test "every code fixture is a heredoc — no escaped string, sigil, or <> concat" do
    bad =
      for path <- files(),
          not Map.has_key?(@allow, path),
          {:ok, ast} = load_ast(path),
          node <- fixtures(ast),
          not fixture_ok?(node),
          uniq: true,
          do: path

    assert Enum.uniq(bad) == [],
           "fixtures that aren't heredocs (use a \"\"\" heredoc):\n" <>
             Enum.map_join(Enum.uniq(bad), "\n", &("  - " <> &1))
  end
end
