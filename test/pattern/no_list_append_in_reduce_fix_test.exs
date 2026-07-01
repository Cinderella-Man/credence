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

      # The surgical patch preserves the input's `list |>` line layout (it only
      # rewrites the reduce step), rather than reflowing it to `list\n|>`.
      expected = """
      defmodule Example do
        def process(list) do
          list |> Enum.reduce([], fn item, acc ->
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

      expected =
        "Enum.reduce(list, [], fn i, acc -> [i | acc] end) |> Enum.reverse() |> Enum.sum()"

      confirm_fix(fix(NoListAppendInReduce, input), expected)
    end
  end

  # In a tighter-than-pipe operator context the reverse wrap must use the CALL
  # form `Enum.reverse(...)`, not the pipe form (which would mis-associate).
  describe "output is valid in operator contexts" do
    test "left operand of ++" do
      confirm_fix(
        fix(NoListAppendInReduce, "Enum.reduce(l, [], fn x, acc -> acc ++ [x] end) ++ [0]"),
        "Enum.reverse(Enum.reduce(l, [], fn x, acc -> [x | acc] end)) ++ [0]"
      )
    end

    test "right operand of ++" do
      confirm_fix(
        fix(NoListAppendInReduce, "[0] ++ Enum.reduce(l, [], fn x, acc -> acc ++ [x] end)"),
        "[0] ++ Enum.reverse(Enum.reduce(l, [], fn x, acc -> [x | acc] end))"
      )
    end

    test "operand of <>" do
      confirm_fix(
        fix(NoListAppendInReduce, "Enum.reduce(l, [], fn x, acc -> acc ++ [x] end) <> bin"),
        "Enum.reverse(Enum.reduce(l, [], fn x, acc -> [x | acc] end)) <> bin"
      )
    end
  end

  # Regression: a piped reduce preceded by other pipe stages must rewrite ONLY
  # the reduce step — the AST-diff path used to mis-attribute the change to a
  # list elsewhere in the chain (corrupting an Ecto `[mb, flow]` join binding into
  # `[[mb, flow]]`). The surgical byte-range patch leaves the upstream untouched.
  describe "does not corrupt upstream pipe stages" do
    test "preceding join/list-arg stages are left byte-for-byte" do
      input = """
      q
      |> join(:inner, [mb], flow in assoc(mb, :flow))
      |> join(:inner, [mb, flow], group in assoc(mb, :group))
      |> Enum.reduce([], fn mb, acc ->
        acc ++ [[mb.flow_name, mb.group_label]]
      end)
      """

      expected = """
      q
      |> join(:inner, [mb], flow in assoc(mb, :flow))
      |> join(:inner, [mb, flow], group in assoc(mb, :group))
      |> Enum.reduce([], fn mb, acc ->
        [[mb.flow_name, mb.group_label] | acc]
      end) |> Enum.reverse()
      """

      confirm_fix(fix(NoListAppendInReduce, input), expected)
    end
  end
end
