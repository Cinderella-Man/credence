defmodule Credence.Pattern.NoParamRebindingTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoParamRebinding.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoParamRebinding.fix(code, [])
  end

  defp fix_and_verify(code) do
    fixed = fix(code)
    {:ok, ast} = Code.string_to_quoted(fixed)
    issues = Credence.Pattern.NoParamRebinding.check(ast, [])
    {fixed, issues}
  end

  describe "check" do
    test "passes code with no parameter rebinding" do
      code = """
      defmodule GoodReduce do
        def process(arr) do
          Enum.reduce(arr, {0, []}, fn x, {count, acc} ->
            new_count = count + 1
            new_acc = [x | acc]
            {new_count, new_acc}
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "detects simple variable rebinding in fn body" do
      code = """
      defmodule BadRebind do
        def process(arr) do
          Enum.reduce(arr, {0, :queue.new()}, fn x, {count, q} ->
            q = :queue.in(x, q)
            count = count + 1
            {count, q}
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &(&1 =~ "q"))
      assert Enum.any?(messages, &(&1 =~ "count"))
    end

    test "detects destructuring rebinding" do
      code = """
      defmodule BadDestructure do
        def process(queue) do
          Enum.reduce(1..5, queue, fn _x, q ->
            {{:value, _h}, q} = :queue.out(q)
            q
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) >= 1
      issue = hd(issues)
      assert issue.message =~ "q"
      assert issue.meta.line != nil
    end

    test "ignores rebinding of variables that are not parameters" do
      code = """
      defmodule SafeLocal do
        def process(list) do
          Enum.map(list, fn x ->
            temp = x * 2
            temp = temp + 1
            temp
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "ignores underscore-prefixed parameters" do
      code = """
      defmodule SafeUnderscore do
        def process(list) do
          Enum.reduce(list, 0, fn _item, acc ->
            acc + 1
          end)
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "renames simple parameter rebinding in Enum.reduce" do
      code = """
      Enum.reduce(arr, {0, :queue.new()}, fn x, {count, q} ->
        q = :queue.in(x, q)
        count = count + 1
        {count, q}
      end)
      """

      {fixed, issues} = fix_and_verify(code)
      assert issues == []
      assert fixed =~ "new_q"
      assert fixed =~ "new_count"
      # RHS must still reference the original parameters
      assert fixed =~ ":queue.in(x, q)"
      assert fixed =~ "count + 1"
    end

    test "renames destructuring rebinding" do
      code = """
      Enum.reduce(1..5, queue, fn _x, q ->
        {{:value, _h}, q} = :queue.out(q)
        q
      end)
      """

      {fixed, issues} = fix_and_verify(code)
      assert issues == []
      assert fixed =~ "new_q"
      assert fixed =~ ":queue.out(q)"
    end

    test "handles multiple parameters rebound independently" do
      code = """
      fn q, r ->
        q = f(q)
        r = g(r)
        {q, r}
      end
      """

      {fixed, issues} = fix_and_verify(code)
      assert issues == []
      assert fixed =~ "new_q = f(q)"
      assert fixed =~ "new_r = g(r)"
    end

    test "preserves parameter references in RHS" do
      code = """
      fn q ->
        q = f(q)
        q
      end
      """

      {fixed, issues} = fix_and_verify(code)
      assert issues == []
      assert fixed =~ "new_q = f(q)"
      refute fixed =~ "new_q = f(new_q)"
    end

    test "does not modify code without rebinding" do
      code = """
      Enum.reduce(arr, {0, []}, fn x, {count, acc} ->
        new_count = count + 1
        new_acc = [x | acc]
        {new_count, new_acc}
      end)
      """

      {fixed, issues} = fix_and_verify(code)
      assert issues == []
      assert fixed =~ "new_count = count + 1"
      assert fixed =~ "new_acc = [x | acc]"
    end

    test "renames references in all subsequent expressions" do
      code = """
      fn q ->
        q = f(q)
        g(q)
        q
      end
      """

      {fixed, issues} = fix_and_verify(code)
      assert issues == []
      assert fixed =~ "new_q = f(q)"
      assert fixed =~ "g(new_q)"
    end

    test "preserves nested fn parameters when names collide" do
      code = """
      fn q ->
        q = f(q)
        Enum.map(list, fn q -> q + 1 end)
        q
      end
      """

      {fixed, issues} = fix_and_verify(code)
      assert issues == []
      assert fixed =~ "new_q = f(q)"
      # The nested fn's own `q` parameter must stay untouched
      assert fixed =~ "fn q ->"
      assert fixed =~ "q + 1"
    end

    test "renames parameter references inside nested fn body" do
      code = """
      fn q ->
        q = f(q)
        Enum.map(list, fn x -> {x, q} end)
        q
      end
      """

      {fixed, issues} = fix_and_verify(code)
      assert issues == []
      assert fixed =~ "new_q = f(q)"
      assert fixed =~ "{x, new_q}"
    end

    test "does not touch standalone code without fn" do
      code = """
      Enum.map(list, fn x -> x + 1 end)
      """

      fixed = fix(code)
      assert fixed =~ "x + 1"
    end

    test "avoids collision with variable names already in the body" do
      code = """
      fn q ->
        new_q = something()
        q = f(q)
        {q, new_q}
      end
      """

      {fixed, _issues} = fix_and_verify(code)
      # Must pick a different name because `new_q` is already used
      assert fixed =~ "new_q_2"
      assert fixed =~ "new_q = something()"
      assert fixed =~ "new_q_2 = f(q)"
    end

    test "fixes rebinding inside complete module" do
      code = """
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

      {fixed, issues} = fix_and_verify(code)
      assert issues == []
      assert fixed =~ "new_q"
      assert fixed =~ "new_count"
    end

    test "handles single-expression fn body" do
      code = """
      fn q -> q = f(q) end
      """

      {fixed, issues} = fix_and_verify(code)
      assert issues == []
      assert fixed =~ "new_q = f(q)"
    end

    test "renames pinned references after rebinding" do
      code = """
      fn q ->
        q = f(q)
        case x do
          ^q -> :matched
          _ -> :unmatched
        end
      end
      """

      {fixed, issues} = fix_and_verify(code)
      assert issues == []
      assert fixed =~ "new_q = f(q)"
      assert fixed =~ "^new_q"
    end
  end
end
