defmodule Credence.Pattern.NoMapGetSentinelCheckTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoMapGetSentinel.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags Map.get with negative integer sentinel and comparison" do
    test "basic != -1" do
      assert flagged?("""
             def run(map) do
               val = Map.get(map, :key, -1)
               if val != -1, do: val, else: :missing
             end
             """)
    end

    test "basic == -1" do
      assert flagged?("""
             def run(map) do
               val = Map.get(map, :key, -1)
               if val == -1, do: :missing, else: val
             end
             """)
    end

    test "sentinel -2" do
      assert flagged?("""
             def run(map) do
               idx = Map.get(map, :pos, -2)
               if idx != -2, do: idx, else: 0
             end
             """)
    end

    test "sentinel -999" do
      assert flagged?("""
             def run(map) do
               val = Map.get(map, :key, -999)
               if val != -999, do: val, else: :default
             end
             """)
    end

    test "strict equality ===" do
      assert flagged?("""
             def run(map) do
               val = Map.get(map, :key, -1)
               if val === -1, do: :missing, else: val
             end
             """)
    end

    test "strict inequality !==" do
      assert flagged?("""
             def run(map) do
               val = Map.get(map, :key, -1)
               if val !== -1, do: val, else: :missing
             end
             """)
    end

    test "compound condition with and" do
      assert flagged?("""
             def run(char_map, grapheme, start_index) do
               last_seen = Map.get(char_map, grapheme, -1)
               if last_seen != -1 and last_seen >= start_index do
                 last_seen + 1
               else
                 start_index
               end
             end
             """)
    end

    test "inside a module" do
      assert flagged?("""
             defmodule Solver do
               def run(cache, key) do
                 val = Map.get(cache, key, -1)
                 if val != -1, do: val, else: compute(key)
               end
             end
             """)
    end

    test "flipped comparison — sentinel on left" do
      assert flagged?("""
             def run(map) do
               val = Map.get(map, :key, -1)
               if -1 != val, do: val, else: :missing
             end
             """)
    end

    test "comparison nested in cond" do
      assert flagged?("""
             def run(map) do
               val = Map.get(map, :key, -1)
               cond do
                 val != -1 -> val
                 true -> :default
               end
             end
             """)
    end

    test "multiple comparisons against same sentinel" do
      assert flagged?("""
             def run(map) do
               val = Map.get(map, :key, -1)
               if val != -1 do
                 process(val)
               end
               if val == -1 do
                 log_miss()
               end
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag non-negative defaults" do
    test "default is 0" do
      assert clean?("""
             def run(map) do
               count = Map.get(map, :count, 0)
               if count != 0, do: count, else: :none
             end
             """)
    end

    test "default is positive integer" do
      assert clean?("""
             def run(map) do
               val = Map.get(map, :key, 1)
               if val != 1, do: val, else: :default
             end
             """)
    end

    test "default is 100" do
      assert clean?("""
             def run(map) do
               val = Map.get(map, :key, 100)
               if val != 100, do: val, else: :default
             end
             """)
    end
  end

  describe "does not flag non-integer defaults" do
    test "default is nil" do
      assert clean?("""
             def run(map) do
               val = Map.get(map, :key, nil)
               if val != nil, do: val, else: :missing
             end
             """)
    end

    test "default is atom" do
      assert clean?("""
             def run(map) do
               val = Map.get(map, :key, :not_found)
               if val != :not_found, do: val, else: :missing
             end
             """)
    end

    test "default is false" do
      assert clean?("""
             def run(map) do
               val = Map.get(map, :enabled, false)
               if val != false, do: :on, else: :off
             end
             """)
    end

    test "default is empty string" do
      assert clean?("""
             def run(map) do
               val = Map.get(map, :name, "")
               if val != "", do: val, else: "anonymous"
             end
             """)
    end

    test "default is empty list" do
      assert clean?("""
             def run(map) do
               val = Map.get(map, :items, [])
               if val != [], do: val, else: [:default]
             end
             """)
    end
  end

  describe "does not flag when no comparison against sentinel" do
    test "sentinel used only in arithmetic" do
      assert clean?("""
             def run(map) do
               val = Map.get(map, :key, -1)
               val + 1
             end
             """)
    end

    test "sentinel passed to function" do
      assert clean?("""
             def run(map) do
               val = Map.get(map, :key, -1)
               process(val)
             end
             """)
    end

    test "comparison uses > not ==" do
      assert clean?("""
             def run(map) do
               val = Map.get(map, :key, -1)
               if val > -1, do: val, else: :negative
             end
             """)
    end

    test "comparison uses >= not ==" do
      assert clean?("""
             def run(map) do
               val = Map.get(map, :key, -1)
               if val >= 0, do: val, else: :missing
             end
             """)
    end
  end

  describe "does not flag when no sentinel default" do
    test "two-arg Map.get" do
      assert clean?("""
             def run(map) do
               val = Map.get(map, :key)
               if val != nil, do: val, else: :missing
             end
             """)
    end
  end

  describe "does not flag scope mismatches" do
    test "Map.get and comparison in different functions" do
      assert clean?("""
             defmodule M do
               def get_val(map), do: Map.get(map, :key, -1)

               def check(val) do
                 if val != -1 do
                   val
                 else
                   :missing
                 end
               end
             end
             """)
    end

    test "variable rebound between Map.get and comparison" do
      assert clean?("""
             def run(map) do
               val = Map.get(map, :key, -1)
               val = transform(val)
               if val != -1, do: val, else: :missing
             end
             """)
    end
  end

  describe "does not flag different variable names" do
    test "comparison on different variable" do
      assert clean?("""
             def run(map) do
               val = Map.get(map, :key, -1)
               other = get_other()
               if other != -1, do: other, else: :missing
             end
             """)
    end
  end

  describe "does not flag comparison against different value" do
    test "sentinel is -1 but comparison against -2" do
      assert clean?("""
             def run(map) do
               val = Map.get(map, :key, -1)
               if val != -2, do: val, else: :missing
             end
             """)
    end
  end

  describe "does not flag non-Map.get calls" do
    test "Keyword.get with sentinel" do
      assert clean?("""
             def run(opts) do
               val = Keyword.get(opts, :key, -1)
               if val != -1, do: val, else: :missing
             end
             """)
    end

    test "Enum.at with negative index" do
      assert clean?("""
             def run(list) do
               val = Enum.at(list, -1)
               if val != -1, do: val, else: :missing
             end
             """)
    end
  end

  describe "fixable?/0" do
    test "reports as fixable" do
      assert Credence.Pattern.NoMapGetSentinel.fixable?() == true
    end
  end
end
