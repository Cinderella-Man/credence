defmodule Credence.Pattern.NoMultiArityFnInStringReplaceCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoMultiArityFnInStringReplace

  describe "flags String.replace with multi-arity anonymous function" do
    test "flags arity-3 fn callback (full match + 2 capture groups)" do
      assert flagged?(NoMultiArityFnInStringReplace, ~S"""
      String.replace(str, pattern, fn _, local, domain -> {local, domain} end)
      """)
    end

    test "flags arity-2 fn callback (full match + 1 capture group)" do
      assert flagged?(NoMultiArityFnInStringReplace, ~S"""
      String.replace(str, pattern, fn match, group -> {match, group} end)
      """)
    end

    test "flags multi-clause fn with arity >= 2" do
      assert flagged?(NoMultiArityFnInStringReplace, ~S"""
      String.replace(str, pattern, fn
        _, group -> group
        match, _ -> match
      end)
      """)
    end

    test "flags multi-arity fn with a guard" do
      assert flagged?(NoMultiArityFnInStringReplace, ~S"""
      String.replace(str, pattern, fn _, group when group != "" -> group end)
      """)
    end
  end

  describe "leaves correct code alone" do
    test "does not flag arity-1 fn callback" do
      assert clean?(NoMultiArityFnInStringReplace, ~S"""
      String.replace(str, pattern, fn match -> String.upcase(match) end)
      """)
    end

    test "does not flag string replacement" do
      assert clean?(NoMultiArityFnInStringReplace, ~S"""
      String.replace(str, pattern, "replacement")
      """)
    end

    test "does not flag Regex.replace with multi-arity fn" do
      assert clean?(NoMultiArityFnInStringReplace, ~S"""
      Regex.replace(pattern, str, fn match, group -> group end)
      """)
    end

    test "does not flag String.replace with no fn argument" do
      assert clean?(NoMultiArityFnInStringReplace, ~S"""
      String.replace(str, pattern, "x")
      """)
    end

    test "does not flag arity-1 fn with a guard" do
      assert clean?(NoMultiArityFnInStringReplace, ~S"""
      String.replace(str, pattern, fn match when match != "" -> match end)
      """)
    end

    test "does not flag the piped form (deliberately out of scope)" do
      assert clean?(NoMultiArityFnInStringReplace, ~S"""
      str |> String.replace(pattern, fn _, group -> group end)
      """)
    end

    test "does not flag a capture as the replacement" do
      assert clean?(NoMultiArityFnInStringReplace, ~S"""
      String.replace(str, pattern, &Helper.rewrite/2)
      """)
    end
  end
end
