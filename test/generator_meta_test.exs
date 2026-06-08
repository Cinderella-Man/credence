defmodule Credence.GeneratorMetaTest do
  @moduledoc """
  The pin that makes `Credence.RuleScaffold` the executable single-source-of-truth
  for "what a valid rule + its tests look like". For each type it generates the
  scaffold in memory (no disk writes), parses every emitted file with Sourceror,
  and asserts — through the **same** `Credence.MetaTestSupport` predicates the real
  gates use — that the output would pass every structural gate:

    * paths and module names match `Credence.RuleName` (the naming gates),
    * the check/analyze test fires in both directions,
    * the fix test makes a real whole-string transform (Pattern/Syntax/Semantic)
      and, for Syntax, reaches an `analyze(fix(x)) == []` fixpoint,
    * the equivalence test (Pattern) asserts and references its rule,
    * Semantic pins its issue attribution,
    * every fixture is a heredoc and no test reaches for the parser.

  So the generator cannot drift from the contract: if a gate's predicate changes,
  the scaffold must keep satisfying it here, or this pin goes red.
  """
  use ExUnit.Case, async: true

  import Credence.MetaTestSupport

  alias Credence.{RuleName, RuleScaffold}

  # Generate a type's scaffold in memory and index the parsed files by kind.
  defp scaffold(name, type) do
    d = RuleName.derive(name, type)
    files = RuleScaffold.files(name, type)

    by_path =
      Map.new(files, fn {path, content} -> {path, parse(content)} end)

    %{
      d: d,
      rule_atom: String.to_atom(d.pascal),
      paths: Enum.map(files, &elem(&1, 0)),
      asts: Map.values(by_path),
      by_path: by_path
    }
  end

  defp ast(s, kind), do: Map.fetch!(s.by_path, RuleName.test_path(s.d, kind))

  # Shapes every type shares: the rule file at its conventional path, every
  # fixture a heredoc, no test reaching for the parser.
  defp assert_common(s) do
    assert s.d.rule_path in s.paths,
           "rule file should be emitted at #{s.d.rule_path}"

    for ast <- s.asts, node <- fixtures(ast) do
      assert fixture_ok?(node), "every fixture must be a heredoc — got #{src(node)}"
    end

    for ast <- s.asts do
      refute walk_any?(ast, &parser_ref?/1),
             "no generated test may reference Code.* / Sourceror.*"
    end
  end

  describe "pattern scaffold passes every Pattern gate" do
    setup do
      %{s: scaffold("PinScaffoldExample", :pattern)}
    end

    test "emits the conventional triplet + heredoc fixtures + no parser refs", %{s: s} do
      assert_common(s)

      assert s.paths == [
               s.d.rule_path,
               RuleName.test_path(s.d, "check"),
               RuleName.test_path(s.d, "fix"),
               RuleName.test_path(s.d, "equivalence")
             ]

      for kind <- ["check", "fix", "equivalence"] do
        assert defines_module?(ast(s, kind), RuleName.test_module(s.d, kind))
      end
    end

    test "check test asserts, references its rule, and fires in both directions", %{s: s} do
      check = ast(s, "check")

      assert calls_any?(check, check_fns())
      assert references_rule?(check, s.rule_atom)
      assert has_positive?(check)
      assert has_negative?(check)
    end

    test "fix test makes a real whole-string transform", %{s: s} do
      fix = ast(s, "fix")

      assert calls_any?(fix, [:fix])
      assert references_rule?(fix, s.rule_atom)
      refute walk_any?(fix, &partial_match?/1)
      assert walk_any?(fix, &transform?/1)
    end

    test "equivalence test asserts and references its rule", %{s: s} do
      equiv = ast(s, "equivalence")

      assert calls_any?(equiv, assert_fns())
      assert references_rule?(equiv, s.rule_atom)
    end
  end

  describe "syntax scaffold passes every Syntax gate" do
    setup do
      %{s: scaffold("PinScaffoldExample", :syntax)}
    end

    test "emits the analyze/fix pair + heredoc fixtures + no parser refs", %{s: s} do
      assert_common(s)

      assert s.paths == [
               s.d.rule_path,
               RuleName.test_path(s.d, "analyze"),
               RuleName.test_path(s.d, "fix")
             ]

      for kind <- ["analyze", "fix"] do
        assert defines_module?(ast(s, kind), RuleName.test_module(s.d, kind))
      end
    end

    test "the union proves both analyze directions, transform, fixpoint, valid output",
         %{s: s} do
      assert Enum.any?(s.asts, &analyze_positive?/1)
      assert Enum.any?(s.asts, &analyze_negative?/1)
      assert Enum.any?(s.asts, fn ast -> walk_any?(ast, &fix_source_transform?/1) end)
      assert Enum.any?(s.asts, fn ast -> walk_any?(ast, &fixpoint?/1) end)
      assert Enum.any?(s.asts, fn ast -> walk_any?(ast, &fix_output_valid?/1) end)
      assert Enum.any?(s.asts, fn ast -> references_rule?(ast, s.rule_atom) end)
    end
  end

  describe "semantic scaffold passes every Semantic gate" do
    setup do
      %{s: scaffold("PinScaffoldExample", :semantic)}
    end

    test "emits the check/fix pair + heredoc fixtures + no parser refs", %{s: s} do
      assert_common(s)

      assert s.paths == [
               s.d.rule_path,
               RuleName.test_path(s.d, "check"),
               RuleName.test_path(s.d, "fix")
             ]

      for kind <- ["check", "fix"] do
        assert defines_module?(ast(s, kind), RuleName.test_module(s.d, kind))
      end
    end

    test "the union proves both match? directions, attribution, transform, valid output",
         %{s: s} do
      assert Enum.any?(s.asts, &asserts_match?/1)
      assert Enum.any?(s.asts, &refutes_match?/1)
      assert Enum.any?(s.asts, fn ast -> references_atom?(ast, s.d.atom) end)
      assert Enum.any?(s.asts, fn ast -> walk_any?(ast, &fix_source_transform?/1) end)
      assert Enum.any?(s.asts, fn ast -> walk_any?(ast, &fix_output_valid?/1) end)
    end
  end
end
