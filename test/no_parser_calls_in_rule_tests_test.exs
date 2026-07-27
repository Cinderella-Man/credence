defmodule Credence.NoParserCallsInRuleTestsTest do
  @moduledoc """
  The gate that keeps the parser out of rule tests. No test under
  `test/pattern`/`test/semantic`/`test/syntax` may reference `Code.*` or
  `Sourceror.*` directly — parsing, fixing, syntax/compile checks and behaviour
  comparison all go through `Credence.RuleCase` (`check`, `flagged?`, `clean?`,
  `fix`, `valid_syntax?`, `compiles?`) and the equivalence harness, which alone
  may touch the parser. `test/support` is exempt (that is where the parser
  legitimately lives).

  Files are introspected with Sourceror, so a `Code.`/`Sourceror.` appearing only
  inside a heredoc fixture (as code-under-test) is a string literal, invisible
  here — only real reference nodes in test logic count.
  """
  use ExUnit.Case, async: true

  # These gates parse every rule module and every rule test file on each run, so
  # they are I/O- and CPU-bound in a way an ordinary unit test is not. Under a
  # full `mix test` the ~20k-file corpus scan runs alongside them and starves
  # them enough to blow the 60s default — observed as a spurious
  # `ExUnit.TimeoutError` in `Credence.SemanticMetaTest`, which passes in 106s
  # for the whole module when run alone. The gate is not slow because anything
  # is wrong; it is slow because it reads the tree.
  @moduletag timeout: :timer.minutes(10)

  import Credence.MetaTestSupport

  @dirs ["test/pattern", "test/semantic", "test/syntax"]

  defp test_files do
    @dirs |> Enum.flat_map(&Path.wildcard("#{&1}/**/*_test.exs")) |> Enum.sort()
  end

  # `parser_ref?/1` lives in `Credence.MetaTestSupport`, so the generator pin
  # asserts against the same code this gate enforces.

  test "no rule test references Code.* or Sourceror.* directly (route through RuleCase)" do
    offenders =
      Enum.filter(test_files(), fn path ->
        case load_ast(path) do
          {:ok, ast} -> walk_any?(ast, &parser_ref?/1)
          :error -> false
        end
      end)

    assert offenders == [],
           "rule tests reaching for the parser instead of RuleCase verbs / the equivalence harness:\n" <>
             Enum.map_join(offenders, "\n", &("  - " <> &1))
  end
end
