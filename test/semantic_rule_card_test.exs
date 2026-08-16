defmodule Credence.SemanticRuleCardTest do
  @moduledoc """
  Requirement 6b for the Semantic round: a documented example must be TRUE.

  Split out of `rule_card_test.exs` and made `async: false` for a reason that
  cost two full-suite runs to find. `Credence.Semantic.analyze/2` COMPILES the
  snippet, and these examples are derived from test fixtures, which share module
  names — `defmodule M` and `defmodule Example` between them. The Erlang code
  server is global, so two async tests compiling `Example` race: one deletes the
  module the other is mid-check on, and the rule appears not to report. Both
  offenders passed when their file was run alone.

  Same root cause as the Pattern half's `async: false`, and the same precedent:
  `dispatch_contention_test.exs`.

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
  use ExUnit.Case, async: false

  alias Credence.RuleDuplication

  defp reports?(rule, source) do
    atom = Credence.RuleName.from_module(rule).atom
    Enum.any?(Credence.Semantic.analyze(source, source: source), &(&1.rule == atom))
  rescue
    _ -> false
  catch
    _, _ -> false
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

    liars = for {rule, snippet} <- examples, not reports?(rule, snippet), do: rule

    assert liars == [],
           """
           These Semantic rules document a `## Bad` example that does not make
           them report through `Credence.Semantic.analyze/2`:

           #{Enum.map_join(liars, "\n  ", &inspect/1)}

           Three causes seen so far. The example may be repaired only on a LATER
           pass, after another rule wins the dispatch slot first — pick a fixture
           where this rule reports directly. A backslash in the example may have
           been collapsed by the moduledoc heredoc. Or the example's module name
           collides with another test's under concurrent compilation, which is
           why this module is `async: false`.
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
end
