defmodule Credence.Pattern.NoListFoldlCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoListFoldl, as: Rule

  describe "flags List.foldl on a provably-list argument" do
    test "list literal" do
      assert flagged?(Rule, "List.foldl([1, 2, 3], 0, fn x, acc -> x + acc end)")
    end

    test "++ concatenation" do
      assert flagged?(Rule, "List.foldl(a ++ b, 0, fn x, acc -> x + acc end)")
    end

    test "direct list-returning call argument" do
      assert flagged?(Rule, "List.foldl(Map.keys(m), 0, fn k, acc -> [k | acc] end)")
    end

    test "piped, last step returns a list" do
      assert flagged?(
               Rule,
               "nums |> Enum.filter(&(&1 > 0)) |> List.foldl(0, fn x, acc -> x + acc end)"
             )
    end
  end

  describe "does NOT flag (argument not provably a list)" do
    test "bare variable" do
      assert clean?(Rule, "List.foldl(list, 0, fn x, acc -> x + acc end)")
    end

    test "piped bare variable" do
      assert clean?(Rule, "list |> List.foldl(0, fn x, acc -> x + acc end)")
    end

    test "range literal (List.foldl would raise, Enum.reduce would not)" do
      assert clean?(Rule, "List.foldl(1..3, 0, fn x, acc -> x + acc end)")
    end

    test "List.foldr is intentionally not covered" do
      assert clean?(Rule, "List.foldr([1, 2, 3], 0, fn x, acc -> x + acc end)")
    end
  end
end
