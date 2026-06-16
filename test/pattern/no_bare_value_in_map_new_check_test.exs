defmodule Credence.Pattern.NoBareValueInMapNewCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoBareValueInMapNew

  describe "flags Map.new/2 with a bare (non-pair) mapper body" do
    test "list literal body" do
      assert flagged?(NoBareValueInMapNew, """
             defmodule M do
               def f(n), do: Map.new(0..(n - 1), fn _k -> [] end)
             end
             """)
    end

    test "number body" do
      assert flagged?(NoBareValueInMapNew, """
             defmodule M do
               def f(items), do: Map.new(items, fn _ -> 0 end)
             end
             """)
    end

    test "string body" do
      assert flagged?(NoBareValueInMapNew, """
             defmodule M do
               def f(items), do: Map.new(items, fn x -> "v" end)
             end
             """)
    end

    test "map literal body" do
      assert flagged?(NoBareValueInMapNew, """
             defmodule M do
               def f(items), do: Map.new(items, fn _ -> %{} end)
             end
             """)
    end
  end

  describe "does not flag working Map.new/2" do
    test "mapper already returns a 2-tuple" do
      assert clean?(NoBareValueInMapNew, """
             defmodule M do
               def f(keys), do: Map.new(keys, fn k -> {k, 0} end)
             end
             """)
    end

    test "mapper body is a call that may return a tuple" do
      assert clean?(NoBareValueInMapNew, """
             defmodule M do
               def f(enum), do: Map.new(enum, fn x -> compute(x) end)
             end
             """)
    end

    test "mapper body is a bare variable (could be a tuple)" do
      assert clean?(NoBareValueInMapNew, """
             defmodule M do
               def f(pairs), do: Map.new(pairs, fn p -> p end)
             end
             """)
    end

    test "destructuring param, not a bare var" do
      assert clean?(NoBareValueInMapNew, """
             defmodule M do
               def f(pairs), do: Map.new(pairs, fn {k, v} -> {k, v} end)
             end
             """)
    end

    test "Map.new/1 (no mapper)" do
      assert clean?(NoBareValueInMapNew, """
             defmodule M do
               def f(pairs), do: Map.new(pairs)
             end
             """)
    end
  end
end
