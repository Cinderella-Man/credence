defmodule Credence.Pattern.NoListAppendInReduceFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoListAppendInReduce

  describe "NoListAppendInReduce fix" do
    test "fixes standalone reduce: ++ to cons + Enum.reverse" do
      input = """
      defmodule Example do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            acc ++ [item * 2]
          end)
        end
      end
      """

      expected = """
      defmodule Example do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            [item * 2 | acc]
          end)
          |> Enum.reverse()
        end
      end
      """

      confirm_fix(fix(NoListAppendInReduce, input), expected)
    end

    test "fixes piped reduce: adds Enum.reverse stage" do
      input = """
      defmodule Example do
        def process(list) do
          list |> Enum.reduce([], fn item, acc ->
            acc ++ [item]
          end)
        end
      end
      """

      expected = """
      defmodule Example do
        def process(list) do
          list
          |> Enum.reduce([], fn item, acc ->
            [item | acc]
          end) |> Enum.reverse()
        end
      end
      """

      confirm_fix(fix(NoListAppendInReduce, input), expected)
    end

    test "fixes multi-line lambda body (only changes last expression)" do
      input = """
      defmodule Example do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            processed = item * 2
            acc ++ [processed]
          end)
        end
      end
      """

      expected = """
      defmodule Example do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            processed = item * 2
            [processed | acc]
          end)
          |> Enum.reverse()
        end
      end
      """

      confirm_fix(fix(NoListAppendInReduce, input), expected)
    end

    test "does not modify reduce with non-empty initial" do
      code = """
      defmodule Example do
        def process(list) do
          Enum.reduce(list, [0], fn item, acc ->
            acc ++ [item]
          end)
        end
      end
      """

      confirm_fix(fix(NoListAppendInReduce, code), code)
    end

    test "does not modify when LHS is not the accumulator" do
      code = """
      defmodule Example do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            other ++ [item]
          end)
        end
      end
      """

      confirm_fix(fix(NoListAppendInReduce, code), code)
    end

    test "does not modify when appending multi-element list" do
      code = """
      defmodule Example do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            acc ++ [item, item + 1]
          end)
        end
      end
      """

      confirm_fix(fix(NoListAppendInReduce, code), code)
    end

    test "fixed code has no remaining issues" do
      code = """
      defmodule Example do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            acc ++ [item * 2]
          end)
        end
      end
      """

      assert check(NoListAppendInReduce, fix(NoListAppendInReduce, code)) == []
    end

    test "fixed piped code has no remaining issues" do
      code = """
      defmodule Example do
        def process(list) do
          list |> Enum.reduce([], fn item, acc ->
            acc ++ [item]
          end)
        end
      end
      """

      assert check(NoListAppendInReduce, fix(NoListAppendInReduce, code)) == []
    end
  end

  # When the reduce result is an operand of an operator binding tighter than `|>`
  # (e.g. `reduce ++ […]`), a trailing `|> Enum.reverse()` would mis-associate and
  # not compile. There the fix uses the precedence-safe CALL form instead.
  describe "operator context uses the call form (Enum.reverse(...))" do
    test "reduce ++ list (the kayrock shape)" do
      input = "Enum.reduce(list, [], fn x, acc -> acc ++ [x] end) ++ [0]"
      expected = "Enum.reverse(Enum.reduce(list, [], fn x, acc -> [x | acc] end)) ++ [0]"

      confirm_fix(fix(NoListAppendInReduce, input), expected)
    end

    test "list ++ reduce (reduce on the right operand)" do
      input = "[0] ++ Enum.reduce(list, [], fn x, acc -> acc ++ [x] end)"
      expected = "[0] ++ Enum.reverse(Enum.reduce(list, [], fn x, acc -> [x | acc] end))"

      confirm_fix(fix(NoListAppendInReduce, input), expected)
    end

    test "piped reduce as an operand of ++" do
      input = "(list |> Enum.reduce([], fn x, acc -> acc ++ [x] end)) ++ [0]"
      expected = "Enum.reverse(list |> Enum.reduce([], fn x, acc -> [x | acc] end)) ++ [0]"

      confirm_fix(fix(NoListAppendInReduce, input), expected)
    end
  end

  # Operators looser than `|>` (assignment), function-argument position, and
  # `|>` chaining itself are all safe, so the idiomatic pipe form is kept.
  describe "safe context keeps the pipe form" do
    test "assignment RHS" do
      input = "x = Enum.reduce(list, [], fn i, acc -> acc ++ [i] end)"
      expected = "x = Enum.reduce(list, [], fn i, acc -> [i | acc] end) |> Enum.reverse()"

      confirm_fix(fix(NoListAppendInReduce, input), expected)
    end

    test "function argument" do
      input = "foo(Enum.reduce(list, [], fn i, acc -> acc ++ [i] end))"
      expected = "foo(Enum.reduce(list, [], fn i, acc -> [i | acc] end) |> Enum.reverse())"

      confirm_fix(fix(NoListAppendInReduce, input), expected)
    end

    test "reduce as the left side of a further pipe" do
      input = "Enum.reduce(list, [], fn i, acc -> acc ++ [i] end) |> Enum.sum()"
      expected = "Enum.reduce(list, [], fn i, acc -> [i | acc] end) |> Enum.reverse() |> Enum.sum()"

      confirm_fix(fix(NoListAppendInReduce, input), expected)
    end
  end

  # The fixed output must always parse and re-fix-clean, in every context.
  describe "output is always valid in operator contexts" do
    for {label, input} <- [
          {"left operand of ++", "Enum.reduce(l, [], fn x, acc -> acc ++ [x] end) ++ [0]"},
          {"right operand of ++", "[0] ++ Enum.reduce(l, [], fn x, acc -> acc ++ [x] end)"},
          {"operand of <>", "Enum.reduce(l, [], fn x, acc -> acc ++ [x] end) <> bin"}
        ] do
      test "parses and is fix-stable: #{label}" do
        fixed = fix(NoListAppendInReduce, unquote(input))
        assert {:ok, _} = Code.string_to_quoted(fixed)
        assert check(NoListAppendInReduce, fixed) == []
      end
    end
  end
end
