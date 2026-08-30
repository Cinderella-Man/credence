defmodule Mix.Tasks.Credence.FiresTest do
  @moduledoc """
  The single-rule reachability probe behind the harness's BUGFIX-lane evidence
  gate (docs/22 T4.2d).

  The property that matters is the three-way answer. A two-way FIRES/INERT
  probe would have to call "I could not ask the question" something, and both
  choices are wrong: INERT fails honest rows, FIRES passes everything. So
  UNKNOWN is its own verdict and the harness is required to treat it as a pass —
  the same inversion `Cev.Premise` exists to avoid.
  """
  use ExUnit.Case, async: true

  alias Mix.Tasks.Credence.Fires

  @counts_map_keys """
  defmodule FiresCountsMapKeys do
    def f(c), do: Enum.count(Map.keys(c))
  end
  """

  describe "FIRES / INERT on the same snippet" do
    test "the rule that engages" do
      assert Fires.verdict("no_enum_count_for_length", @counts_map_keys) == "FIRES"
    end

    test "a rule that does not — this is the only answer allowed to fail a row" do
      assert Fires.verdict("no_manual_max", @counts_map_keys) == "INERT"
    end
  end

  describe "naming a rule" do
    test "accepts the full module, the last segment, and the snake_case file name" do
      for spelling <- [
            "Credence.Pattern.NoEnumCountForLength",
            "Elixir.Credence.Pattern.NoEnumCountForLength",
            "NoEnumCountForLength",
            "no_enum_count_for_length"
          ] do
        assert Fires.verdict(spelling, @counts_map_keys) == "FIRES", "failed for #{spelling}"
      end
    end

    test "a name that matches no rule is UNKNOWN, never INERT" do
      assert Fires.verdict("no_such_rule_at_all", @counts_map_keys) == "UNKNOWN"
      assert Fires.resolve("no_such_rule_at_all") == nil
    end
  end

  describe "all three phases are reachable" do
    test "semantic — engagement via a real compiler diagnostic" do
      source = """
      defmodule FiresSemanticDefpstruct do
        defpstructp now: 0
      end
      """

      assert Fires.verdict("no_hallucinated_defpstruct", source) == "FIRES"
    end

    test "syntax — engagement on source that does not parse" do
      source = """
      defmodule FiresSyntaxElsif do
        def f(a) do
          if a do
            1
          elsif a do
            2
          end
        end
      end
      """

      assert Fires.verdict("fix_elsif_in_if_chain", source) == "FIRES"
    end
  end

  describe "a rule that engages without changing anything still counts" do
    test "a declined match is engagement, not absence" do
      # The rule claims `:after` and then declines, because an `else` riding
      # alongside has no faithful `try` rewrite. A no-op is exactly the shape a
      # BUGFIX report is often about, so it must read FIRES rather than INERT —
      # this is why the probe counts every trace outcome and not just a change.
      source = """
      defmodule FiresDeclinedMatch do
        def f(x) do
          case x do
            :a -> :ok
          after
            IO.puts("done")
          else
            _ -> :err
          end
        end
      end
      """

      assert Fires.verdict("fix_after_or_rescue_in_case", source) == "FIRES"
    end

    test "but not claiming a diagnostic at all reads INERT, and should" do
      # Same construct, clauses swapped. Elixir reports the FIRST unexpected
      # option, so this compiles to `unexpected option :else in "case"` — which
      # this rule deliberately does not match, because it has no repair for it.
      # Declining to match is cleaner than matching and no-opping, and the probe
      # is right to call the difference.
      source = """
      defmodule FiresUnclaimedDiagnostic do
        def f(x) do
          case x do
            :a -> :ok
          else
            _ -> :err
          after
            IO.puts("done")
          end
        end
      end
      """

      assert Fires.verdict("fix_after_or_rescue_in_case", source) == "INERT"
    end
  end
end
