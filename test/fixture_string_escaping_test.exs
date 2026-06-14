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

  # `allow/0`, `fixtures/1`, and `fixture_ok?/1` all live in
  # `Credence.MetaTestSupport` — single source of truth, shared with
  # `Credence.FixtureHealer` (which heals everything this gate would flag).

  defp files do
    @dirs |> Enum.flat_map(&Path.wildcard("#{&1}/**/*_test.exs")) |> Enum.sort()
  end

  # `fixtures/1` and `fixture_ok?/1` live in `Credence.MetaTestSupport`, so the
  # generator pin asserts against the same code this gate enforces.

  test "every code fixture is canonical — plain single-line / ~S'…' / heredoc" do
    bad =
      for path <- files(),
          not Map.has_key?(allow(), path),
          {:ok, ast} = load_ast(path),
          node <- fixtures(ast),
          not fixture_ok?(node),
          uniq: true,
          do: path

    assert Enum.uniq(bad) == [],
           "non-canonical fixtures (single-line → \"…\"; with a quote → ~S'…'; " <>
             "multi-line → a \"\"\" heredoc):\n" <>
             Enum.map_join(Enum.uniq(bad), "\n", &("  - " <> &1))
  end
end
