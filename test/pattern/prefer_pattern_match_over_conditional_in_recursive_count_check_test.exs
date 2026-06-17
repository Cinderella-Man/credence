defmodule Credence.Pattern.PreferPatternMatchOverConditionalInRecursiveCountCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferPatternMatchOverConditionalInRecursiveCount

  test "flags the anti-pattern" do
    assert flagged?(PreferPatternMatchOverConditionalInRecursiveCount, """
           defmodule Example do
             def count_until([], _target, _stop), do: 0
             def count_until([stop | _rest], _target, stop), do: 0
             def count_until([head | tail], target, stop) do
               count = if head == target, do: 1, else: 0
               count + count_until(tail, target, stop)
             end
           end
           """)
  end

  test "flags without stop parameter" do
    assert flagged?(PreferPatternMatchOverConditionalInRecursiveCount, """
           defmodule Example do
             def count([], _target), do: 0
             def count([head | tail], target) do
               count = if head == target, do: 1, else: 0
               count + count(tail, target)
             end
           end
           """)
  end

  test "leaves code with no conditional alone" do
    assert clean?(PreferPatternMatchOverConditionalInRecursiveCount, """
           defmodule Example do
             def count_until([], _target, _stop), do: 0
             def count_until([stop | _rest], _target, stop), do: 0
             def count_until([target | tail], target, stop), do: 1 + count_until(tail, target, stop)
             def count_until([_head | tail], target, stop), do: count_until(tail, target, stop)
           end
           """)
  end

  test "leaves non-recursive if alone" do
    assert clean?(PreferPatternMatchOverConditionalInRecursiveCount, """
           defmodule Example do
             def process([head | tail], target) do
               count = if head == target, do: 1, else: 0
               count + other_fn(tail)
             end
           end
           """)
  end

  test "leaves non-counting recursive if alone" do
    assert clean?(PreferPatternMatchOverConditionalInRecursiveCount, """
           defmodule Example do
             def transform([head | tail], target) do
               result = if head == target, do: head * 2, else: head
               result + transform(tail, target)
             end
           end
           """)
  end

  test "flags strict-equality (===) counting" do
    assert flagged?(PreferPatternMatchOverConditionalInRecursiveCount, """
           defmodule Example do
             def count([], _target), do: 0
             def count([head | tail], target) do
               count = if head === target, do: 1, else: 0
               count + count(tail, target)
             end
           end
           """)
  end

  test "leaves a body with an extra statement alone" do
    assert clean?(PreferPatternMatchOverConditionalInRecursiveCount, """
           defmodule Example do
             def count([head | tail], target) do
               count = if head == target, do: 1, else: 0
               IO.puts(head)
               count + count(tail, target)
             end
           end
           """)
  end

  test "leaves recursion with differing args alone" do
    assert clean?(PreferPatternMatchOverConditionalInRecursiveCount, """
           defmodule Example do
             def count([head | tail], target, acc) do
               count = if head == target, do: 1, else: 0
               count + count(tail, target, acc + 1)
             end
           end
           """)
  end
end
