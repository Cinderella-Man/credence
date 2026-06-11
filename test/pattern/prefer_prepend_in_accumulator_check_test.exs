defmodule Credence.Pattern.PreferPrependInAccumulatorCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferPrependInAccumulator

  describe "PreferPrependInAccumulator check" do
    # --- POSITIVE CASES ---

    test "flags List.last(acc) with acc ++ [next] and Enum.reverse(acc) in recursive function" do
      code = """
      defmodule Bad do
        def build_groups(acc, []) do
          [Enum.reverse(acc)]
        end

        def build_groups(acc, [next | rest]) do
          last = List.last(acc)

          if next == last + 1 do
            build_groups(acc ++ [next], rest)
          else
            [Enum.reverse(acc) | build_groups([next], rest)]
          end
        end
      end
      """

      issues = check(PreferPrependInAccumulator, code)
      assert length(issues) == 1
      issue = hd(issues)
      assert issue.rule == :prefer_prepend_in_accumulator
      assert issue.message =~ "List.last(acc)"
      assert issue.message =~ "acc ++ [expr]"
      assert issue.meta.line != nil
    end

    # --- NEGATIVE CASES ---

    test "does not flag idiomatic prepend with head pattern match" do
      code = """
      defmodule Good do
        def build_groups(acc, []) do
          [acc]
        end

        def build_groups([head | _] = acc, [next | rest]) do
          if next == head + 1 do
            build_groups([next | acc], rest)
          else
            [acc | build_groups([next], rest)]
          end
        end
      end
      """

      assert clean?(PreferPrependInAccumulator, code)
    end

    test "does not flag List.last without ++ append" do
      code = """
      defmodule OnlyLast do
        def process(acc, [next | rest]) do
          last = List.last(acc)
          process([last + next | acc], rest)
        end
      end
      """

      assert clean?(PreferPrependInAccumulator, code)
    end

    test "does not flag ++ append without List.last" do
      code = """
      defmodule OnlyAppend do
        def process(acc, [next | rest]) do
          process(acc ++ [next], rest)
        end
      end
      """

      assert clean?(PreferPrependInAccumulator, code)
    end

    test "does not flag List.last + append without Enum.reverse" do
      code = """
      defmodule NoReverse do
        def build(acc, []) do
          acc
        end

        def build(acc, [next | rest]) do
          last = List.last(acc)

          if next == last + 1 do
            build(acc ++ [next], rest)
          else
            [acc | build([next], rest)]
          end
        end
      end
      """

      assert clean?(PreferPrependInAccumulator, code)
    end
  end
end
