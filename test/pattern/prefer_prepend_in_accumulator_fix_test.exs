defmodule Credence.Pattern.PreferPrependInAccumulatorFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferPrependInAccumulator

  describe "PreferPrependInAccumulator fix" do
    test "rewrites List.last + append to head pattern match + prepend, removing Enum.reverse" do
      input = """
      defmodule Example do
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

      # Run the fix and verify it produces valid output
      result = fix(PreferPrependInAccumulator, input)

      # The fix should:
      # 1. Change acc → [head | _] = acc in second clause
      # 2. Remove `last = List.last(acc)` and replace `last` → `head`
      # 3. Change acc ++ [next] → [next | acc]
      # 4. Change Enum.reverse(acc) → acc
      assert fix(PreferPrependInAccumulator, input) == """
      defmodule Example do
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
      assert valid_syntax?(result)
    end

    test "does not fix idiomatic code" do
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

      assert fix(PreferPrependInAccumulator, code) == code
    end

    test "does not fix List.last without ++ append" do
      code = """
      defmodule OnlyLast do
        def process(acc, [next | rest]) do
          last = List.last(acc)
          process([last + next | acc], rest)
        end
      end
      """

      assert fix(PreferPrependInAccumulator, code) == code
    end

    test "does not fix ++ append without List.last" do
      code = """
      defmodule OnlyAppend do
        def process(acc, [next | rest]) do
          process(acc ++ [next], rest)
        end
      end
      """

      assert fix(PreferPrependInAccumulator, code) == code
    end

    test "does not fix List.last + append without Enum.reverse" do
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

      assert fix(PreferPrependInAccumulator, code) == code
    end

    test "fixed code has no remaining issues" do
      code = """
      defmodule Example do
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

      assert check(PreferPrependInAccumulator, fix(PreferPrependInAccumulator, code)) == []
    end
  end
end
