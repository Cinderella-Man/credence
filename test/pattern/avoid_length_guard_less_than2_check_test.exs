defmodule Credence.Pattern.AvoidLengthGuardLessThan2CheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.AvoidLengthGuardLessThan2

  describe "flags the anti-pattern" do
    test "length(list) < 2" do
      assert flagged?(
               AvoidLengthGuardLessThan2,
               "def process(list) when length(list) < 2, do: :ok"
             )
    end

    test "length(list) <= 1" do
      assert flagged?(
               AvoidLengthGuardLessThan2,
               "def process(list) when length(list) <= 1, do: :ok"
             )
    end

    test "2 > length(list) — reversed" do
      assert flagged?(
               AvoidLengthGuardLessThan2,
               "def process(list) when 2 > length(list), do: :ok"
             )
    end

    test "1 >= length(list) — reversed" do
      assert flagged?(
               AvoidLengthGuardLessThan2,
               "def process(list) when 1 >= length(list), do: :ok"
             )
    end

    test "defp variant" do
      assert flagged?(
               AvoidLengthGuardLessThan2,
               "defp process(list) when length(list) < 2, do: :ok"
             )
    end

    test "inside a module" do
      assert flagged?(AvoidLengthGuardLessThan2, """
             defmodule Example do
               def maximumdifference(list) when length(list) < 2, do: 0
             end
             """)
    end
  end

  describe "does NOT flag" do
    test "length(list) < 3 (different threshold)" do
      assert clean?(AvoidLengthGuardLessThan2, "def process(list) when length(list) < 3, do: :ok")
    end

    test "length(list) > 0 (different comparison)" do
      assert clean?(AvoidLengthGuardLessThan2, "def process(list) when length(list) > 0, do: :ok")
    end

    test "no guard" do
      assert clean?(AvoidLengthGuardLessThan2, "def process(list), do: :ok")
    end

    test "length(list) == 0" do
      assert clean?(
               AvoidLengthGuardLessThan2,
               "def process(list) when length(list) == 0, do: :ok"
             )
    end

    test "pattern-matched empty list" do
      assert clean?(AvoidLengthGuardLessThan2, "def process([]), do: :ok")
    end

    test "pattern-matched single element" do
      assert clean?(AvoidLengthGuardLessThan2, "def process([_]), do: :ok")
    end

    # Compound guards are the safe-core boundary: splitting into `[]`/`[_]`
    # clauses would drop the remaining condition, so the rule must not fire.
    test "compound `and` guard (length < 2 and ...)" do
      assert clean?(
               AvoidLengthGuardLessThan2,
               "def process(list) when length(list) < 2 and is_list(list), do: :ok"
             )
    end

    test "compound `or` guard (length <= 1 or ...)" do
      assert clean?(
               AvoidLengthGuardLessThan2,
               "def process(list) when length(list) <= 1 or list == nil, do: :ok"
             )
    end
  end
end
