defmodule Credence.Pattern.NoKeywordGetWithAtomFirstArgEquivalenceTest do
  use Credence.RuleCase, async: true
  import Credence.BehaviourEquivalence

  alias Credence.Pattern.NoKeywordGetWithAtomFirstArg

  test "does not rewrite calls when a custom module is aliased as Keyword" do
    source = """
    defmodule NoKeywordGetAliasShadowFixture do
      defmodule CustomKeyword do
        def get(:clock, default), do: {:custom, default}
      end

      alias CustomKeyword, as: Keyword

      def run(default), do: Keyword.get(:clock, default)
    end
    """

    assert check(NoKeywordGetWithAtomFirstArg, source) == []
    emitted = fix(NoKeywordGetWithAtomFirstArg, source)
    confirm_fix(emitted, source)
  end

  test "unshadowed Keyword calls with an atom first argument are repairs" do
    assert :ok =
             mark_equivalence_repair(
               "Unshadowed `Keyword.get(:atom, ...)` calls target Elixir's Keyword module, " <>
                 "whose keyword-list guard raises for every atom/default combination."
             )
  end
end
