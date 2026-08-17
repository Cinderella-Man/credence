defmodule Credence.SemanticRuleCardTest do
  @moduledoc """
  Requirement 6b for the Semantic round: a documented example must be TRUE.

  Split out of `rule_card_test.exs` because `Credence.Semantic.analyze/2`
  COMPILES the snippet, which made it the third place a module-name collision
  bit: the examples inherited their fixtures' names, `defmodule M` and
  `defmodule Example` among them, and two async tests compiling `Example` race
  on the global code server. Both offenders passed when run alone.

  That is fixed at the source now — every example module name is unique, derived
  from its rule, and `rule_card_test.exs` gates the uniqueness — so this file no
  longer needs to be serial. It stays a separate module because it is the
  Semantic half of requirement 6b and reads better beside its own controls.

  ## What this found

  Two pre-existing examples were false, and neither was visible by reading:
  `FixWithElseBareValue` and `NoRescueInWithExpression` each documented a `with`
  snippet their own rule never reports on.

  Backfilling the other 80 found a third hazard worth recording, because it will
  bite anyone who generates documentation from fixtures. A `@moduledoc` heredoc
  COLLAPSES a backslash, so `def foo(a, b \\\\ :ok)` — a default argument — comes
  back out of the doc as `b \\ :ok`, which is not one. The rule silently stopped
  reporting on its own example. `#{}` is worse still: it is interpolation, and
  the heredoc EVALUATES it at module-compile time. Both have to be escaped, and
  the backslash first, since escaping `#{}` introduces one of its own.
  """
  use ExUnit.Case, async: true

  alias Credence.RuleDuplication

  # Three outcomes, not two. `:silent` is an accusation — the rule was asked about
  # its own documented example and said nothing. `:could_not_tell` is not, and
  # collapsing the two is how this gate learned to lie.
  #
  # `Semantic.analyze/2` COMPILES the snippet, and that compile is bounded by a
  # wall clock and a heap ceiling (`RuleHelpers.compile_and_capture/1`). When either
  # trips, it returns `{:error, [%{message: "credence: compilation aborted — …"}]}`,
  # no rule matches that diagnostic, `analyze/2` returns `[]` — and the old
  # `rescue _ -> false` rendered "we never ran the analysis" as "the example is
  # false". Under a loaded full suite the ceilings do trip: the run that exposed
  # this named `FixNimbleCsvDirectParse`, which passes on its own.
  defp verdict(rule, source) do
    atom = Credence.RuleName.from_module(rule).atom

    if Enum.any?(Credence.Semantic.analyze(source, source: source), &(&1.rule == atom)),
      do: :reports,
      else: :silent
  rescue
    _ -> :could_not_tell
  catch
    _, _ -> :could_not_tell
  end

  # The controls below ask a yes/no question about a snippet they construct, where
  # an unanalysable compile would be a bug in the control rather than a load
  # artefact — so they keep the two-valued form.
  defp reports?(rule, source), do: verdict(rule, source) == :reports

  # Only asked about a snippet that already came back `:silent`, so the extra
  # compile costs nothing on a green run — and on a red one it is the difference
  # between a real finding and a false accusation.
  defp aborted?(source) do
    match?(
      {:error, [%{message: "credence: compilation aborted" <> _} | _]},
      Credence.RuleHelpers.compile_and_capture(source)
    )
  rescue
    _ -> true
  catch
    _, _ -> true
  end

  test "every Semantic `## Bad` example makes its own rule report" do
    examples =
      for rule <- Credence.Semantic.default_rules(),
          snippet = RuleDuplication.bad_example(rule),
          snippet not in [nil, ""],
          do: {rule, snippet}

    # Population floor, not a result check: if the extractor breaks, every rule
    # silently has "no example" and this passes by testing nothing.
    assert length(examples) >= 86,
           "only #{length(examples)} Semantic Bad examples extracted; the extractor has regressed"

    suspects =
      for {rule, snippet} <- examples, verdict(rule, snippet) != :reports, do: {rule, snippet}

    {unprovable, liars} =
      suspects
      |> Enum.split_with(fn {_rule, snippet} -> aborted?(snippet) end)
      |> then(fn {u, l} -> {Enum.map(u, &elem(&1, 0)), Enum.map(l, &elem(&1, 0))} end)

    if unprovable != [] do
      IO.warn("""
      #{length(unprovable)} Semantic example(s) could not be analysed at all — the
      compile hit its wall-clock or heap ceiling, which happens under a loaded run:

          #{Enum.map_join(unprovable, "\n    ", &inspect/1)}

      These are NOT counted as false examples. Re-run this file alone to judge them.
      """)
    end

    assert liars == [],
           """
           These Semantic rules document a `## Bad` example that does not make
           them report through `Credence.Semantic.analyze/2`:

           #{Enum.map_join(liars, "\n  ", &inspect/1)}

           Three causes seen so far. The example may be repaired only on a LATER
           pass, after another rule wins the dispatch slot first — pick a fixture
           where this rule reports directly. A backslash in the example may have
           been collapsed by the moduledoc heredoc. Or the example's module name
           collides with another rule's example under concurrent compilation —
           `rule_card_test.exs` gates that names stay unique.
           """
  end

  test "no Semantic `## Good` example makes its own rule report" do
    liars =
      for rule <- Credence.Semantic.default_rules(),
          snippet = RuleDuplication.good_example(rule),
          snippet not in [nil, ""],
          reports?(rule, snippet),
          do: rule

    assert liars == [],
           """
           These rules report on the example their own moduledoc holds up as
           correct — so either the rule over-reports or the documentation is
           teaching the wrong idiom:

           #{Enum.map_join(liars, "\n  ", &inspect/1)}
           """
  end

  # The predicate decides both tests, and one that answered `true` for
  # everything would make the second vacuous while the first stayed green.
  test "CONTROL: reports?/2 is false for a source the rule has nothing to say about" do
    refute reports?(
             Credence.Semantic.UnusedVariable,
             "defmodule SemRcClean do\n  def f(x), do: x\nend\n"
           )
  end

  test "CONTROL: reports?/2 is true for a source that really trips the rule" do
    assert reports?(
             Credence.Semantic.UnusedVariable,
             "defmodule SemRcDirty do\n  def f(x) do\n    y = x + 1\n    :ok\n  end\nend\n"
           )
  end

  # The guard above is only worth having if it can be seen to fire. `@runaway` is
  # `compile_bounds_test.exs`'s fixture: a source that never finishes allocating,
  # so `compile_and_capture/1` kills it on the heap ceiling and returns an abort
  # diagnostic. That is precisely the state the old `rescue _ -> false` reported as
  # "this rule's documented example is false".
  describe "an unanalysable compile is not evidence against a rule" do
    @runaway "Enum.flat_map(1..10, &Stream.cycle([&1]))"

    test "the abort is detected" do
      assert aborted?(@runaway)
    end

    test "CONTROL: ordinary source is not treated as aborted" do
      refute aborted?("defmodule SemanticCardControl do\n  def f, do: :ok\nend\n")
    end

    # The whole point, stated as the two-step it is: analysis says nothing, and
    # that silence must not be read as a verdict.
    test "an aborted example reads as :could_not_tell, never as :silent" do
      rule = List.first(Credence.Semantic.default_rules())

      assert verdict(rule, @runaway) == :silent,
             "analyze/2 returns [] for an aborted compile — that is the trap"

      assert aborted?(@runaway),
             "so the second question is what separates it from a real liar"
    end
  end
end
