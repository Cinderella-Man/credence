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

  test "rewrites multi-arity fn with a guard" do
    input = ~S'String.replace(str, pattern, fn _, group when group != "" -> group end)'
    expected = ~S'Regex.replace(pattern, str, fn _, group when group != "" -> group end)'
    confirm_fix(fix(NoMultiArityFnInStringReplace, input), expected)
  end

  test "rewrites a multi-line call with a regex literal inside a module" do
    input = ~S"""
    defmodule CredenceNoMultiArityFnInStringReplacePipelineFixture do
      def anonymize(text) do
        String.replace(text, ~r/([a-z]+)@([a-z]+)/, fn _, local, domain ->
          "#{String.first(local)}***@#{domain}"
        end)
      end
    end
    """

    expected = ~S"""
    defmodule CredenceNoMultiArityFnInStringReplacePipelineFixture do
      def anonymize(text) do
        Regex.replace(~r/([a-z]+)@([a-z]+)/, text, fn _, local, domain ->
          "#{String.first(local)}***@#{domain}"
        end)
      end
    end
    """

    confirm_fix(fix(NoMultiArityFnInStringReplace, input), expected)
    pipeline_output = Credence.Pattern.fix(input)
    confirm_fix(pipeline_output, expected)
  end

  test "rewrites both calls when two occurrences appear" do
    input = ~S"""
    a = String.replace(x, p1, fn _, g -> g end)
    b = String.replace(y, p2, fn m, _ -> m end)
    """

    expected = ~S"""
    a = Regex.replace(p1, x, fn _, g -> g end)
    b = Regex.replace(p2, y, fn m, _ -> m end)
    """

    confirm_fix(fix(NoMultiArityFnInStringReplace, input), expected)
  end

  test "does not modify the piped form (deliberately out of scope)" do
    input = ~S'str |> String.replace(pattern, fn _, group -> group end)'
    confirm_fix(fix(NoMultiArityFnInStringReplace, input), input)
  end

  test "does not modify a capture replacement" do
    input = ~S'String.replace(str, pattern, &Helper.rewrite/2)'
    confirm_fix(fix(NoMultiArityFnInStringReplace, input), input)
  end
end
