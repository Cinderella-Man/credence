defmodule Credence.RuleTestCompletenessTest do
  @moduledoc """
  The gate that every Pattern rule ships its full test **triplet**, named by the
  one convention. Rule `Credence.Pattern.NoFoo` must have, in `test/pattern/`:

    * `no_foo_check_test.exs`       defining `Credence.Pattern.NoFooCheckTest`
    * `no_foo_fix_test.exs`         defining `Credence.Pattern.NoFooFixTest`
    * `no_foo_equivalence_test.exs` defining `Credence.Pattern.NoFooEquivalenceTest`

  So a rule can't land with a missing or mis-named check/fix/equivalence file —
  the drift that single-`_test.exs` files and "Check"-suffixed rule names used to
  slip past. `EquivalenceMetaTest` layers the deeper equivalence-specific checks
  (a real assertion, references the rule, no skeleton) on top of the existence
  gate here.

  Test files are introspected with Sourceror, like everything else in this project
  (no `Code.string_to_quoted`).
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

  @kinds ["check", "fix", "equivalence"]

  # Paths/module names come from `Credence.RuleName` (the one naming source of
  # truth) and the AST membership check from `Credence.MetaTestSupport`, so the
  # generator pin asserts against the same convention this gate enforces.
  defp specs do
    for rule <- Credence.RuleHelpers.discover_rules(Credence.Pattern.Rule),
        derived = Credence.RuleName.from_module(rule),
        kind <- @kinds do
      %{
        rule: rule,
        kind: kind,
        path: Credence.RuleName.test_path(derived, kind),
        module: Credence.RuleName.test_module(derived, kind)
      }
    end
  end

  defp bullets(entries, line), do: Enum.map_join(entries, "\n", &("  - " <> line.(&1)))

  defp defines_module?(path, module) do
    case Credence.MetaTestSupport.load_ast(path) do
      {:ok, ast} -> Credence.MetaTestSupport.defines_module?(ast, module)
      :error -> false
    end
  end

  test "every Pattern rule has all three test files, correctly named" do
    missing = Enum.reject(specs(), fn s -> File.exists?(s.path) end)

    assert missing == [],
           "rules missing a test file in the check/fix/equivalence triplet:\n" <>
             bullets(missing, fn s -> "#{inspect(s.rule)} — expected #{s.path}" end)
  end

  test "each triplet test file defines the conventionally-named module" do
    mismatched =
      specs()
      |> Enum.filter(fn s -> File.exists?(s.path) end)
      |> Enum.reject(fn s -> defines_module?(s.path, s.module) end)

    assert mismatched == [],
           "triplet test files that don't define their expected module:\n" <>
             bullets(mismatched, fn s -> "#{s.path} — should define #{inspect(s.module)}" end)
  end
end
