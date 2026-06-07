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

  @kinds [{"check", "CheckTest"}, {"fix", "FixTest"}, {"equivalence", "EquivalenceTest"}]

  defp specs do
    for rule <- Credence.RuleHelpers.discover_rules(Credence.Pattern.Rule),
        {kind, suffix} <- @kinds do
      short = rule |> Module.split() |> List.last()

      %{
        rule: rule,
        kind: kind,
        path: "test/pattern/#{Macro.underscore(short)}_#{kind}_test.exs",
        module: Module.concat([Credence, Pattern, :"#{short}#{suffix}"])
      }
    end
  end

  defp bullets(entries, line), do: Enum.map_join(entries, "\n", &("  - " <> line.(&1)))

  defp defines_module?(path, module) do
    parts = Module.split(module) |> Enum.map(&String.to_atom/1)

    path
    |> File.read!()
    |> Sourceror.parse_string!()
    |> Macro.prewalk(false, fn
      {:defmodule, _, [{:__aliases__, _, ^parts} | _]} = node, _ -> {node, true}
      node, acc -> {node, acc}
    end)
    |> elem(1)
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
