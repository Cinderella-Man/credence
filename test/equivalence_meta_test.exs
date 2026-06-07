defmodule Credence.EquivalenceMetaTest do
  @moduledoc """
  The gate that guarantees every rule is really tested for behaviour preservation.

  For each `Credence.Pattern.Rule`, this enforces four things — so a rule cannot
  ship with a missing, hollow, or mislabelled equivalence test (which a careless
  author, human or agent, could otherwise slip past):

    1. **It has its own file, named after the rule.** Rule `Credence.Pattern.NoFoo`
       must have `test/pattern/no_foo_equivalence_test.exs`, and that file must
       define `Credence.Pattern.NoFooEquivalenceTest`. (No hunting through other
       files for a matching module name.)
    2. **The test actually asserts something.** The file must call one of the real
       checks — `assert_equivalent`, `assert_equivalent_module`,
       `assert_effect_trace_equivalent` — or an explicit, reasoned opt-out
       (`mark_equivalence_cosmetic` / `_unconstructible` / `_repair`). An empty
       module named for the rule no longer passes.
    3. **An assertion-based test names the rule it covers.** If the file uses a real
       check, it must reference the rule module itself (e.g. `rule: NoFoo`), so the
       test is about this rule, not some other one. (Opt-out marks are exempt — the
       file name already identifies the rule.)
    4. **No test is still an unfilled skeleton** (`:equivalence_todo`).
  """
  use ExUnit.Case, async: true

  @assert_fns [:assert_equivalent, :assert_equivalent_module, :assert_effect_trace_equivalent]
  @mark_fns [
    :mark_equivalence_cosmetic,
    :mark_equivalence_unconstructible,
    :mark_equivalence_repair
  ]

  defp rules, do: Credence.RuleHelpers.discover_rules(Credence.Pattern.Rule)

  # Inspect each rule's expected test file and report what is / isn't there.
  defp analyze_all, do: Enum.map(rules(), &analyze/1)

  defp analyze(rule) do
    short = rule |> Module.split() |> List.last()
    path = "test/pattern/#{Macro.underscore(short)}_equivalence_test.exs"
    module_parts = [:Credence, :Pattern, String.to_atom(short <> "EquivalenceTest")]

    base = %{rule: rule, short: short, path: path}

    case load_ast(path) do
      {:ok, ast} ->
        Map.merge(base, %{
          file_exists: true,
          defines_module: defines_module?(ast, module_parts),
          has_real_assert: calls_any?(ast, @assert_fns),
          has_mark: calls_any?(ast, @mark_fns),
          references_rule: references_alias?(ast, String.to_atom(short))
        })

      :error ->
        Map.merge(base, %{
          file_exists: false,
          defines_module: false,
          has_real_assert: false,
          has_mark: false,
          references_rule: false
        })
    end
  end

  defp load_ast(path) do
    with true <- File.exists?(path),
         {:ok, ast} <- Code.string_to_quoted(File.read!(path)) do
      {:ok, ast}
    else
      _ -> :error
    end
  end

  # Does the AST contain `defmodule <parts> do ... end`?
  defp defines_module?(ast, parts) do
    walk_any?(ast, fn
      {:defmodule, _, [{:__aliases__, _, ^parts}, _]} -> true
      _ -> false
    end)
  end

  # Does the AST call any of `names` (bare calls — the helpers are imported)?
  defp calls_any?(ast, names) do
    walk_any?(ast, fn
      {name, _, args} when is_atom(name) and is_list(args) -> name in names
      _ -> false
    end)
  end

  # Does any module reference (`__aliases__`) end in `last_atom`? Catches both
  # `alias Credence.Pattern.NoFoo` and a bare `NoFoo` usage; the test module's own
  # name ends in `NoFooEquivalenceTest`, so it never matches the rule's atom.
  defp references_alias?(ast, last_atom) do
    walk_any?(ast, fn
      {:__aliases__, _, parts} when is_list(parts) -> List.last(parts) == last_atom
      _ -> false
    end)
  end

  defp walk_any?(ast, pred) do
    {_, found} =
      Macro.prewalk(ast, false, fn node, acc -> {node, acc or pred.(node)} end)

    found
  end

  defp bullets(entries, line) do
    Enum.map_join(entries, "\n", fn e -> "  - " <> line.(e) end)
  end

  test "1. every rule has its own <name>_equivalence_test.exs defining <Name>EquivalenceTest" do
    bad = Enum.reject(analyze_all(), fn a -> a.file_exists and a.defines_module end)

    assert bad == [],
           "rules whose equivalence test file is missing or mis-named:\n" <>
             bullets(bad, fn a ->
               reason =
                 if a.file_exists,
                   do: "file exists but does not define #{a.short}EquivalenceTest",
                   else: "file not found"

               "#{inspect(a.rule)} — expected #{a.path} (#{reason})"
             end)
  end

  test "2. every rule's equivalence test makes a real assertion or an explicit opt-out mark" do
    bad =
      analyze_all()
      |> Enum.filter(fn a -> a.file_exists and a.defines_module end)
      |> Enum.reject(fn a -> a.has_real_assert or a.has_mark end)

    assert bad == [],
           "rules whose equivalence test asserts nothing (no assert_equivalent* and no " <>
             "mark_equivalence_* opt-out — a hollow module):\n" <>
             bullets(bad, fn a -> "#{inspect(a.rule)} — #{a.path}" end)
  end

  test "3. every assertion-based equivalence test references the rule it covers" do
    bad =
      analyze_all()
      |> Enum.filter(fn a -> a.file_exists and a.has_real_assert end)
      |> Enum.reject(fn a -> a.references_rule end)

    assert bad == [],
           "rules whose equivalence test uses a real check but never references the rule " <>
             "module (so it may be testing the wrong rule):\n" <>
             bullets(bad, fn a -> "#{inspect(a.rule)} — #{a.path}" end)
  end

  test "4. no behaviour-equivalence test is still an un-filled skeleton (:equivalence_todo)" do
    skeletons =
      "test/pattern/*_equivalence_test.exs"
      |> Path.wildcard()
      |> Enum.filter(fn path -> String.contains?(File.read!(path), "equivalence_todo") end)
      |> Enum.sort()

    assert skeletons == [],
           "skeleton equivalence tests still tagged :equivalence_todo " <>
             "(fill them — the backfill is meant to be complete):\n" <>
             Enum.map_join(skeletons, "\n", &("  - " <> &1))
  end
end
