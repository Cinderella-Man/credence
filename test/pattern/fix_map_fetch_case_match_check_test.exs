defmodule Credence.Pattern.FixMapFetchCaseMatchCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.FixMapFetchCaseMatch

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — bare map pattern in a case Map.fetch success clause
  # ═══════════════════════════════════════════════════════════════════

  describe "flags bare map patterns in case Map.fetch" do
    test "bare map-match pattern (%{...} = var)" do
      assert flagged?(FixMapFetchCaseMatch, """
             case Map.fetch(state, key) do
               :error -> :err
               %{callers: callers} = info -> info
             end
             """)
    end

    test "bare map literal pattern (%{...})" do
      assert flagged?(FixMapFetchCaseMatch, """
             case Map.fetch(state, key) do
               :error -> :err
               %{callers: callers} -> callers
             end
             """)
    end

    test "flags inside a function def" do
      assert flagged?(FixMapFetchCaseMatch, """
             def process(state, key, from) do
               case Map.fetch(state, key) do
                 :error ->
                   Map.put(state, key, %{callers: [from]})

                 %{callers: callers} = info ->
                   Map.put(state, key, %{info | callers: [from | callers]})
               end
             end
             """)
    end

    test "flags with bare map first, error second" do
      assert flagged?(FixMapFetchCaseMatch, """
             case Map.fetch(m, k) do
               %{x: x} -> x
               :error -> nil
             end
             """)
    end

    test "flags multiple bare map patterns" do
      code = """
      defmodule Multi do
        def a(m, k) do
          case Map.fetch(m, k) do
            :error -> nil
            %{a: a} = v -> v
          end
        end

        def b(m, k) do
          case Map.fetch(m, k) do
            :error -> nil
            %{b: b} -> b
          end
        end
      end
      """

      assert length(check(FixMapFetchCaseMatch, code)) == 2
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag correct patterns" do
    test "already wrapped in {:ok, ...}" do
      assert clean?(FixMapFetchCaseMatch, """
             case Map.fetch(state, key) do
               :error -> :err
               {:ok, %{callers: callers} = info} -> info
             end
             """)
    end

    test "already wrapped {:ok, _}" do
      assert clean?(FixMapFetchCaseMatch, """
             case Map.fetch(state, key) do
               :error -> nil
               {:ok, val} -> val
             end
             """)
    end

    test "non-Map.fetch case with bare map pattern" do
      assert clean?(FixMapFetchCaseMatch, """
             case something do
               :error -> nil
               %{x: x} -> x
             end
             """)
    end

    test "Map.get, not Map.fetch" do
      assert clean?(FixMapFetchCaseMatch, """
             case Map.get(state, key) do
               :error -> nil
               %{x: x} -> x
             end
             """)
    end

    test "bare variable pattern (not a map)" do
      assert clean?(FixMapFetchCaseMatch, """
             case Map.fetch(state, key) do
               :error -> nil
               val -> val
             end
             """)
    end

    test "tuple pattern (not a map)" do
      assert clean?(FixMapFetchCaseMatch, """
             case Map.fetch(state, key) do
               :error -> nil
               {:ok, val} -> val
             end
             """)
    end
  end
end
