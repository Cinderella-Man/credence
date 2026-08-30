defmodule Credence.Pattern.PreferMultiClauseReduceFnFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferMultiClauseReduceFn

  test "rewrites nested if/else to multi-clause with guards" do
    input = """
    Enum.reduce(list, {nil, 0}, fn element, {candidate, count} ->
      if count == 0 do
        {element, 1}
      else
        if element == candidate do
          {candidate, count + 1}
        else
          {candidate, count - 1}
        end
      end
    end)
    """

    expected = """
    Enum.reduce(list, {nil, 0}, fn
      element, {candidate, count} when count == 0 -> {element, 1}
      element, {candidate, count} when element == candidate -> {candidate, count + 1}
      _element, {candidate, count} -> {candidate, count - 1}
    end)
    """

    confirm_fix(fix(PreferMultiClauseReduceFn, input), expected)
  end

  test "does not modify non-reduce code" do
    code = "Enum.reduce(list, 0, fn x, acc -> x + acc end)"

    confirm_fix(fix(PreferMultiClauseReduceFn, code), code)
  end

  test "does not modify already multi-clause reduce" do
    code = """
    Enum.reduce(list, {nil, 0}, fn
      element, {candidate, count} when count == 0 -> {element, 1}
      element, {candidate, count} when element == candidate -> {candidate, count + 1}
      _element, {candidate, count} -> {candidate, count - 1}
    end)
    """

    confirm_fix(fix(PreferMultiClauseReduceFn, code), code)
  end

  test "does not modify single-level if/else" do
    code = """
    Enum.reduce(list, 0, fn num, acc ->
      if rem(num, 2) == 0, do: acc + num, else: acc
    end)
    """

    confirm_fix(fix(PreferMultiClauseReduceFn, code), code)
  end

  test "round-trip: fixed code produces no issues" do
    code = """
    Enum.reduce(list, {nil, 0}, fn element, {candidate, count} ->
      if count == 0 do
        {element, 1}
      else
        if element == candidate do
          {candidate, count + 1}
        else
          {candidate, count - 1}
        end
      end
    end)
    """

    assert check(PreferMultiClauseReduceFn, fix(PreferMultiClauseReduceFn, code)) == []
  end

  test "uses a fresh name when underscoring an unused first parameter" do
    input = """
    result = Enum.reduce([1], {2, 1}, fn element, {_element, count} ->
      if count == 0 do
        {:zero, count}
      else
        if count == 1 do
          {:one, count}
        else
          {:other, count}
        end
      end
    end)
    unless result == {:one, 1}, do: raise("wrong result")
    """

    expected = """
    result = Enum.reduce([1], {2, 1}, fn
      _element2, {_element, count} when count == 0 -> {:zero, count}
      _element2, {_element, count} when count == 1 -> {:one, count}
      _element2, {_element, count} -> {:other, count}
    end)
    unless result == {:one, 1}, do: raise("wrong result")
    """

    emitted = fix(PreferMultiClauseReduceFn, input)

    assert [emitted] == [expected]
    assert {:ok, _diagnostics} = Credence.RuleHelpers.compile_and_capture(input)
    assert {:ok, _diagnostics} = Credence.RuleHelpers.compile_and_capture(emitted)
  end
end
