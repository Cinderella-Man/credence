defmodule Credence.Pattern.NoMultiArityFnInStringReplaceFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoMultiArityFnInStringReplace

  test "rewrites String.replace to Regex.replace with swapped args" do
    input = ~S'String.replace(str, pattern, fn _, g1, g2 -> {g1, g2} end)'
    expected = ~S'Regex.replace(pattern, str, fn _, g1, g2 -> {g1, g2} end)'
    confirm_fix(fix(NoMultiArityFnInStringReplace, input), expected)
  end

  test "rewrites arity-2 fn" do
    input = ~S'String.replace(str, pattern, fn match, group -> {match, group} end)'
    expected = ~S'Regex.replace(pattern, str, fn match, group -> {match, group} end)'
    confirm_fix(fix(NoMultiArityFnInStringReplace, input), expected)
  end

  test "does not modify arity-1 fn" do
    input = ~S'String.replace(str, pattern, fn match -> String.upcase(match) end)'
    confirm_fix(fix(NoMultiArityFnInStringReplace, input), input)
  end

  test "does not modify string replacement" do
    input = ~S'String.replace(str, pattern, "replacement")'
    confirm_fix(fix(NoMultiArityFnInStringReplace, input), input)
  end

  test "does not modify Regex.replace with multi-arity fn" do
    input = ~S'Regex.replace(pattern, str, fn match, group -> group end)'
    confirm_fix(fix(NoMultiArityFnInStringReplace, input), input)
  end
end
