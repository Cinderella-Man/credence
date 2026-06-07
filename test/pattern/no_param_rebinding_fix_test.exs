defmodule Credence.Pattern.NoParamRebindingFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoParamRebinding

  describe "fix" do
    test "renames simple parameter rebinding in Enum.reduce" do
      input = """
      Enum.reduce(arr, {0, :queue.new()}, fn x, {count, q} ->
        q = :queue.in(x, q)
        count = count + 1
        {count, q}
      end)
      """

      expected = """
      Enum.reduce(arr, {0, :queue.new()}, fn x, {count, q} ->
        new_q = :queue.in(x, q)
        new_count = count + 1
        {new_count, new_q}
      end)
      """

      assert fix(NoParamRebinding, input) == expected
    end

    test "renames destructuring rebinding" do
      input = """
      Enum.reduce(1..5, queue, fn _x, q ->
        {{:value, _h}, q} = :queue.out(q)
        q
      end)
      """

      expected = """
      Enum.reduce(1..5, queue, fn _x, q ->
        {{:value, _h}, new_q} = :queue.out(q)
        new_q
      end)
      """

      assert fix(NoParamRebinding, input) == expected
    end

    test "handles multiple parameters rebound independently" do
      input = """
      fn q, r ->
        q = f(q)
        r = g(r)
        {q, r}
      end
      """

      expected = """
      fn q, r ->
        new_q = f(q)
        new_r = g(r)
        {new_q, new_r}
      end
      """

      assert fix(NoParamRebinding, input) == expected
    end

    test "preserves parameter references in RHS" do
      input = """
      fn q ->
        q = f(q)
        q
      end
      """

      expected = """
      fn q ->
        new_q = f(q)
        new_q
      end
      """

      assert fix(NoParamRebinding, input) == expected
    end

    test "does not modify code without rebinding" do
      code = """
      Enum.reduce(arr, {0, []}, fn x, {count, acc} ->
        new_count = count + 1
        new_acc = [x | acc]
        {new_count, new_acc}
      end)
      """

      assert fix(NoParamRebinding, code) == code
    end

    test "renames references in all subsequent expressions" do
      input = """
      fn q ->
        q = f(q)
        g(q)
        q
      end
      """

      expected = """
      fn q ->
        new_q = f(q)
        g(new_q)
        new_q
      end
      """

      assert fix(NoParamRebinding, input) == expected
    end

    test "preserves nested fn parameters when names collide" do
      input = """
      fn q ->
        q = f(q)
        Enum.map(list, fn q -> q + 1 end)
        q
      end
      """

      expected = """
      fn q ->
        new_q = f(q)
        Enum.map(list, fn q -> q + 1 end)
        new_q
      end
      """

      assert fix(NoParamRebinding, input) == expected
    end

    test "renames parameter references inside nested fn body" do
      input = """
      fn q ->
        q = f(q)
        Enum.map(list, fn x -> {x, q} end)
        q
      end
      """

      expected = """
      fn q ->
        new_q = f(q)
        Enum.map(list, fn x -> {x, new_q} end)
        new_q
      end
      """

      assert fix(NoParamRebinding, input) == expected
    end

    test "does not touch standalone code without fn" do
      code = """
      Enum.map(list, fn x -> x + 1 end)
      """

      assert fix(NoParamRebinding, code) == code
    end

    test "avoids collision with variable names already in the body" do
      input = """
      fn q ->
        new_q = something()
        q = f(q)
        {q, new_q}
      end
      """

      expected = """
      fn q ->
        new_q = something()
        new_q_2 = f(q)
        {new_q_2, new_q}
      end
      """

      assert fix(NoParamRebinding, input) == expected
    end

    test "fixes rebinding inside complete module" do
      input = """
      defmodule FullExample do
        def process(arr) do
          Enum.reduce(arr, {0, :queue.new()}, fn x, {count, q} ->
            q = :queue.in(x, q)
            count = count + 1
            {count, q}
          end)
        end
      end
      """

      expected = """
      defmodule FullExample do
        def process(arr) do
          Enum.reduce(arr, {0, :queue.new()}, fn x, {count, q} ->
            new_q = :queue.in(x, q)
            new_count = count + 1
            {new_count, new_q}
          end)
        end
      end
      """

      assert fix(NoParamRebinding, input) == expected
    end

    test "handles single-expression fn body" do
      input = """
      fn q -> q = f(q) end
      """

      expected = """
      fn q -> new_q = f(q) end
      """

      assert fix(NoParamRebinding, input) == expected
    end

    test "renames pinned references after rebinding" do
      input = """
      fn q ->
        q = f(q)
        case x do
          ^q -> :matched
          _ -> :unmatched
        end
      end
      """

      expected = """
      fn q ->
        new_q = f(q)
        case x do
          ^new_q -> :matched
          _ -> :unmatched
        end
      end
      """

      assert fix(NoParamRebinding, input) == expected
    end
  end
end
