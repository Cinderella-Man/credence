defmodule Credence.Pattern.NoKeywordGetIntegerKeyCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoKeywordGetIntegerKey

  # ── flags integer keys ─────────────────────────────────────────

  describe "flags integer keys" do
    test "negative index -1" do
      assert [%Issue{rule: :no_keyword_get_integer_key}] =
               check(NoKeywordGetIntegerKey, "Keyword.get(acc, -1)")
    end

    test "zero index" do
      assert [%Issue{}] =
               check(NoKeywordGetIntegerKey, "Keyword.get(list, 0)")
    end

    test "positive index" do
      assert [%Issue{}] =
               check(NoKeywordGetIntegerKey, "Keyword.get(items, 3)")
    end

    test "other negative index" do
      assert [%Issue{}] =
               check(NoKeywordGetIntegerKey, "Keyword.get(items, -2)")
    end
  end

  # ── flags in various contexts ──────────────────────────────────

  describe "flags in various contexts" do
    test "in assignment" do
      assert [%Issue{}] =
               check(NoKeywordGetIntegerKey, "prev = Keyword.get(acc, -1)")
    end

    test "in pipe" do
      assert [%Issue{}] =
               check(NoKeywordGetIntegerKey, "acc |> Keyword.get(-1)")
    end

    test "as function argument" do
      assert [%Issue{}] =
               check(NoKeywordGetIntegerKey, "do_something(Keyword.get(list, -1))")
    end
  end

  # ── flags multiple violations ──────────────────────────────────

  describe "flags multiple violations" do
    test "two in one module" do
      code = """
      defmodule E do
        def first(l), do: Keyword.get(l, 0)
        def last(l), do: Keyword.get(l, -1)
      end
      """

      assert length(check(NoKeywordGetIntegerKey, code)) == 2
    end
  end

  # ── does NOT flag ──────────────────────────────────────────────

  describe "does NOT flag" do
    test "atom key" do
      assert check(NoKeywordGetIntegerKey, "Keyword.get(opts, :name)") == []
    end

    test "atom key with default" do
      assert check(NoKeywordGetIntegerKey, ~S'Keyword.get(opts, :name, "default")') == []
    end

    test "variable key" do
      assert check(NoKeywordGetIntegerKey, "Keyword.get(opts, key)") == []
    end

    test "Map.get with integer key (maps allow integer keys)" do
      assert check(NoKeywordGetIntegerKey, "Map.get(map, -1)") == []
    end

    test "Keyword.fetch with integer key (different function)" do
      assert check(NoKeywordGetIntegerKey, "Keyword.fetch(opts, -1)") == []
    end

    test "no Keyword.get at all" do
      assert check(NoKeywordGetIntegerKey, "List.last(acc)") == []
    end

    # Piped `opts |> Keyword.get(:atom, default)` desugars to Keyword.get/3 — the
    # integer is the DEFAULT, not the key. Must not be flagged.
    test "piped Keyword.get with atom key and integer default" do
      assert check(NoKeywordGetIntegerKey, "opts |> Keyword.get(:timeout, 5000)") == []
    end

    test "direct 3-arg Keyword.get with atom key and integer default" do
      assert check(NoKeywordGetIntegerKey, "Keyword.get(opts, :timeout, 5000)") == []
    end
  end

  # ── metadata ───────────────────────────────────────────────────

  describe "metadata" do
    test "meta.line is set" do
      [issue] =
        check(NoKeywordGetIntegerKey, "Keyword.get(acc, -1)")

      assert issue.meta.line != nil
    end
  end

  # The boundary with `NoKeywordGetWithAtomFirstArg`. `Keyword.get(:timeout, 5000)`
  # has an integer second argument, but it is not an integer-KEY lookup — it is
  # that rule's swapped-arguments defect, repaired by unwrapping to the second
  # argument. `Enum.at(:timeout, 5000)` would be nonsense, and two rules claiming
  # one defect is dispatch contention.
  #
  # This was previously masked, not handled: the fix required a bare identifier as
  # the first argument, which excluded an atom literal by accident, while this
  # check reported it anyway. Widening the fix removed the accident and exposed the
  # over-report, which `rule_self_repair_test` then caught as the sibling's own
  # `## Bad` example failing to survive the pipeline.
  describe "an atom-literal first argument belongs to the sibling rule" do
    test "Keyword.get(:timeout, 5000) is not ours" do
      assert check(NoKeywordGetIntegerKey, "Keyword.get(:timeout, 5000)") == []
    end

    test "the sibling rule does claim it" do
      assert flagged?(
               Credence.Pattern.NoKeywordGetWithAtomFirstArg,
               "Keyword.get(:timeout, 5000)"
             )
    end

    test "a non-atom first argument with an integer key is still ours" do
      assert check(NoKeywordGetIntegerKey, "Keyword.get(timeout, 5000)") != []
    end
  end
end
