defmodule Credence.FixtureStringEscapingTest do
  @moduledoc """
  The gate that keeps every **code fixture** in the project's single canonical
  form — exactly one shape per value, no exceptions (no file allow-list):

    * single-line, no `"`  → plain `"…"`
    * single-line, has `"` → `~S'…'` sigil
    * has an internal newline → `\"""` heredoc

  Scoped to **fixture positions** (the code-under-test): a string passed to a rule
  verb (`check`/`fix`/`clean?`/…/`assert_equivalent`), compared to one with `==` or
  `confirm_fix`, or assigned to `code`/`input`/`expected`/`source`/…. Non-fixtures
  — a `=~` message-substring, a `mark_equivalence_*` reason, a `\#{}` fragment in a
  list — are not checked; they legitimately stay plain.

  Introspected with Sourceror (delimiter-aware). A single-content-line heredoc
  (`\"""\\nfoo\\n\"""`, value `"foo\\n"`) is **not** canonical — it must be a plain
  `"…"` / `~S'…'`. The healer (`Credence.FixtureHealer`) produces exactly this
  form, so this gate only ever flags residue it can't mechanically convert.
  """
  use ExUnit.Case, async: true

  import Credence.MetaTestSupport

  @dirs ["test/pattern", "test/semantic", "test/syntax"]

  defp files do
    @dirs |> Enum.flat_map(&Path.wildcard("#{&1}/**/*_test.exs")) |> Enum.sort()
  end

  # `fixtures/1` and `fixture_ok?/1` live in `Credence.MetaTestSupport`, so the
  # generator pin asserts against the same code this gate enforces.

  test "every code fixture is canonical — plain single-line / ~S'…' / heredoc" do
    bad =
      for path <- files(),
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
