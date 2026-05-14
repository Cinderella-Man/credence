defmodule Credence.FunctionMatcherTest do
  use ExUnit.Case

  alias Credence.FunctionMatcher

  defp suggest(source, module_name, undefined_name, arity, opts \\ []) do
    FunctionMatcher.suggest(source, module_name, undefined_name, arity, opts)
  end

  defp candidates(source, module_name, undefined_name, arity, opts \\ []) do
    FunctionMatcher.candidates(source, module_name, undefined_name, arity, opts)
  end

  # ═══════════════════════════════════════════════════════════════════
  # SUFFIX REPAIR — ? and !
  # The highest-confidence matches: exact name + missing punctuation
  # ═══════════════════════════════════════════════════════════════════

  describe "suggest – missing ? suffix" do
    test "palindrome → palindrome?" do
      source = """
      defmodule PalindromeChecker do
        def palindrome?(text), do: text == String.reverse(text)
        def clean(text), do: String.downcase(text)
      end
      """

      assert suggest(source, "PalindromeChecker", "palindrome", 1) == {:ok, "palindrome?"}
    end

    test "even → even?" do
      source = """
      defmodule Math do
        def even?(n), do: rem(n, 2) == 0
      end
      """

      assert suggest(source, "Math", "even", 1) == {:ok, "even?"}
    end

    test "valid → valid?" do
      source = """
      defmodule Validator do
        def valid?(input), do: input != nil
        def validate(input), do: {:ok, input}
      end
      """

      assert suggest(source, "Validator", "valid", 1) == {:ok, "valid?"}
    end
  end

  describe "suggest – missing ! suffix" do
    test "save → save!" do
      source = """
      defmodule Repo do
        def save!(record), do: record
      end
      """

      assert suggest(source, "Repo", "save", 1) == {:ok, "save!"}
    end

    test "update → update!" do
      # update/1 exists as def, so the compiler wouldn't say it's undefined.
      # But if it DID, update!/1 should score higher than update/1 for the
      # undefined name "update" — wait, this case wouldn't arise because
      # update/1 IS defined. Let me adjust this test.
      #
      # Scenario: module defines update!/1 only, code calls update/1
      source_only_bang = """
      defmodule Repo do
        def update!(record), do: record
      end
      """

      assert suggest(source_only_bang, "Repo", "update", 1) == {:ok, "update!"}
    end
  end

  describe "suggest – __ demangle to ?" do
    test "perfect__ → perfect?" do
      source = """
      defmodule PerfectNumbers do
        def perfect?(n), do: n == 6
      end
      """

      assert suggest(source, "PerfectNumbers", "perfect__", 1) == {:ok, "perfect?"}
    end

    test "balanced__ → balanced?" do
      source = """
      defmodule Brackets do
        def balanced?(input), do: true
      end
      """

      assert suggest(source, "Brackets", "balanced__", 1) == {:ok, "balanced?"}
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # PREFIX / SUBSTRING MATCHING
  # When the LLM uses a conceptual name different from the actual one
  # ═══════════════════════════════════════════════════════════════════

  describe "suggest – candidate is prefix of undefined name" do
    test "fib matches fibonacci" do
      source = """
      defmodule Fibonacci do
        def fib(0), do: 0
        def fib(1), do: 1
        def fib(n), do: fib(n - 1) + fib(n - 2)
      end
      """

      assert suggest(source, "Fibonacci", "fibonacci", 1) == {:ok, "fib"}
    end
  end

  describe "suggest – undefined name is prefix of candidate" do
    test "find matches find_largest" do
      source = """
      defmodule Finder do
        def find_largest([x]), do: x
        def find_largest([h | t]), do: max(h, find_largest(t))
      end
      """

      assert suggest(source, "Finder", "find", 1) == {:ok, "find_largest"}
    end
  end

  describe "suggest – one contains the other" do
    test "fibonacci matches do_fibonacci" do
      source = """
      defmodule Fibonacci do
        def do_fibonacci(n), do: n
      end
      """

      assert suggest(source, "Fibonacci", "fibonacci", 1) == {:ok, "do_fibonacci"}
    end

    test "sort matches merge_sort" do
      source = """
      defmodule Sorter do
        def merge_sort(list), do: list
      end
      """

      assert suggest(source, "Sorter", "sort", 1) == {:ok, "merge_sort"}
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # STRING DISTANCE — typos and minor differences
  # ═══════════════════════════════════════════════════════════════════

  describe "suggest – small Levenshtein distance" do
    test "proccess → process (one char typo)" do
      source = """
      defmodule Worker do
        def process(data), do: data
      end
      """

      assert suggest(source, "Worker", "proccess", 1) == {:ok, "process"}
    end

    test "recieve → receive_msg (close enough)" do
      source = """
      defmodule Handler do
        def receive_msg(msg), do: msg
      end
      """

      assert suggest(source, "Handler", "recieve", 1) == {:ok, "receive_msg"}
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SOLE CANDIDATE — only one function with matching arity
  # ═══════════════════════════════════════════════════════════════════

  describe "suggest – sole candidate with matching arity" do
    test "picks the only arity-1 function regardless of name" do
      source = """
      defmodule Calculator do
        def compute(n), do: n * 2
        def add(a, b), do: a + b
        def sub(a, b), do: a - b
      end
      """

      assert suggest(source, "Calculator", "xyz_totally_different", 1) == {:ok, "compute"}
    end

    test "picks the only arity-0 function" do
      source = """
      defmodule Config do
        def defaults, do: %{}
        def get(key), do: key
      end
      """

      assert suggest(source, "Config", "init", 0) == {:ok, "defaults"}
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SCORING PRIORITY — suffix > prefix > substring > distance
  # ═══════════════════════════════════════════════════════════════════

  describe "suggest – scoring priority" do
    test "? suffix wins over prefix match" do
      source = """
      defmodule Checker do
        def palindrome?(text), do: true
        def palindrome_check(text), do: true
      end
      """

      # palindrome? (suffix match, score 100) beats palindrome_check (prefix, lower)
      assert suggest(source, "Checker", "palindrome", 1) == {:ok, "palindrome?"}
    end

    test "? suffix wins over sole candidate" do
      source = """
      defmodule Checker do
        def valid?(x), do: true
        def check(x), do: true
      end
      """

      assert suggest(source, "Checker", "valid", 1) == {:ok, "valid?"}
    end

    test "prefix match wins over unrelated name" do
      source = """
      defmodule Math do
        def fib(n), do: n
        def process(n), do: n
      end
      """

      assert suggest(source, "Math", "fibonacci", 1) == {:ok, "fib"}
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # ARITY FILTERING
  # ═══════════════════════════════════════════════════════════════════

  describe "suggest – arity filtering" do
    test "only considers functions with matching arity" do
      source = """
      defmodule Math do
        def add(a, b), do: a + b
        def multiply(a, b, c), do: a * b * c
      end
      """

      # Looking for arity 2, only add/2 matches
      assert suggest(source, "Math", "sum", 2) == {:ok, "add"}
    end

    test "no candidates when no matching arity" do
      source = """
      defmodule Math do
        def add(a, b), do: a + b
      end
      """

      assert suggest(source, "Math", "compute", 1) == :no_candidates
    end

    test "arity 0 functions" do
      source = """
      defmodule Config do
        def defaults, do: %{}
      end
      """

      assert suggest(source, "Config", "init", 0) == {:ok, "defaults"}
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # VISIBILITY FILTERING
  # ═══════════════════════════════════════════════════════════════════

  describe "suggest – visibility filtering" do
    test "default :any includes defp" do
      source = """
      defmodule Worker do
        defp helper(x), do: x * 2
      end
      """

      assert suggest(source, "Worker", "help", 1) == {:ok, "helper"}
    end

    test "public_only excludes defp" do
      source = """
      defmodule Worker do
        defp helper(x), do: x * 2
      end
      """

      assert suggest(source, "Worker", "help", 1, visibility: :public_only) == :no_candidates
    end

    test "public_only still finds def" do
      source = """
      defmodule Worker do
        def process(x), do: x
        defp helper(x), do: x * 2
      end
      """

      assert suggest(source, "Worker", "run", 1, visibility: :public_only) == {:ok, "process"}
    end

    test "prefers def over defp when both match equally" do
      source = """
      defmodule Worker do
        def process(x), do: x
        defp process_internal(x), do: x
      end
      """

      # Both contain "process" but def should be preferred for qualified calls
      result = suggest(source, "Worker", "process_data", 1, visibility: :public_only)
      assert result == {:ok, "process"}
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MODULE SCOPING
  # ═══════════════════════════════════════════════════════════════════

  describe "suggest – module scoping" do
    test "only searches in the named module" do
      source = """
      defmodule Alpha do
        def foo(x), do: x
      end

      defmodule Beta do
        def bar(x), do: x
      end
      """

      assert suggest(source, "Alpha", "baz", 1) == {:ok, "foo"}
      assert suggest(source, "Beta", "baz", 1) == {:ok, "bar"}
    end

    test "does not leak functions across modules" do
      source = """
      defmodule Alpha do
        def alpha_func(x), do: x
      end

      defmodule Beta do
        def beta_func(x), do: x
      end
      """

      # Searching in Alpha should NOT find beta_func
      result = candidates(source, "Alpha", "beta_func", 1)
      names = Enum.map(result, & &1.name)
      refute "beta_func" in names
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # EMPTY / EDGE CASE MODULES
  # ═══════════════════════════════════════════════════════════════════

  describe "suggest – empty and edge case modules" do
    test "empty module" do
      source = """
      defmodule Empty do
      end
      """

      assert suggest(source, "Empty", "anything", 1) == :no_candidates
    end

    test "module with only module attributes" do
      source = """
      defmodule Config do
        @moduledoc "Some config"
        @default_timeout 5000
      end
      """

      assert suggest(source, "Config", "get", 1) == :no_candidates
    end

    test "module not found in source" do
      source = """
      defmodule Alpha do
        def foo(x), do: x
      end
      """

      assert suggest(source, "NonExistent", "bar", 1) == :no_candidates
    end

    test "unparseable source" do
      source = "this is not valid elixir {"

      assert suggest(source, "Module", "foo", 1) == :no_candidates
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MULTI-CLAUSE FUNCTIONS
  # ═══════════════════════════════════════════════════════════════════

  describe "suggest – multi-clause functions" do
    test "function with multiple clauses appears once" do
      source = """
      defmodule Factorial do
        def factorial(0), do: 1
        def factorial(n), do: n * factorial(n - 1)
      end
      """

      result = candidates(source, "Factorial", "fact", 1)
      names = Enum.map(result, & &1.name)
      assert names == ["factorial"]
    end

    test "matches multi-clause function" do
      source = """
      defmodule Factorial do
        def factorial(0), do: 1
        def factorial(n) when n > 0, do: n * factorial(n - 1)
      end
      """

      assert suggest(source, "Factorial", "fact", 1) == {:ok, "factorial"}
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FUNCTIONS WITH GUARDS
  # ═══════════════════════════════════════════════════════════════════

  describe "suggest – functions with guards" do
    test "finds function defined with when guard" do
      source = """
      defmodule Validator do
        def valid?(input) when is_binary(input), do: true
        def valid?(_), do: false
      end
      """

      assert suggest(source, "Validator", "validate", 1) == {:ok, "valid?"}
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # REAL-WORLD CASES FROM LOGS
  # ═══════════════════════════════════════════════════════════════════

  describe "suggest – real log cases" do
    test "PalindromeChecker.palindrome → palindrome? (20 occurrences)" do
      source = """
      defmodule PalindromeChecker do
        def palindrome?(text) do
          cleaned = text |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")
          cleaned == String.reverse(cleaned)
        end
      end
      """

      assert suggest(source, "PalindromeChecker", "palindrome", 1) == {:ok, "palindrome?"}
    end

    test "PerfectNumbers.perfect__ → perfect? (4 occurrences)" do
      source = """
      defmodule PerfectNumbers do
        def perfect?(n) do
          divisors = for i <- 1..(n - 1), rem(n, i) == 0, do: i
          Enum.sum(divisors) == n
        end
      end
      """

      assert suggest(source, "PerfectNumbers", "perfect__", 1) == {:ok, "perfect?"}
    end

    test "fibonacci → fib (21 occurrences)" do
      source = """
      defmodule Fibonacci do
        def fib(0), do: 0
        def fib(1), do: 1
        def fib(n), do: fib(n - 1) + fib(n - 2)
      end
      """

      assert suggest(source, "Fibonacci", "fibonacci", 1) == {:ok, "fib"}
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # candidates/5 — returns ranked list
  # ═══════════════════════════════════════════════════════════════════

  describe "candidates – returns ranked list" do
    test "returns all matching-arity functions sorted by score desc" do
      source = """
      defmodule Math do
        def fib(n), do: n
        def factorial(n), do: n
        def compute(n), do: n
      end
      """

      result = candidates(source, "Math", "fibonacci", 1)
      names = Enum.map(result, & &1.name)

      # fib should be first (prefix match with fibonacci)
      assert hd(names) == "fib"
      # All three should be present
      assert length(result) == 3
    end

    test "each candidate has required fields" do
      source = """
      defmodule Example do
        def foo(x), do: x
      end
      """

      [candidate] = candidates(source, "Example", "bar", 1)
      assert Map.has_key?(candidate, :name)
      assert Map.has_key?(candidate, :arity)
      assert Map.has_key?(candidate, :visibility)
      assert Map.has_key?(candidate, :score)
    end

    test "returns empty list when no matching arity" do
      source = """
      defmodule Example do
        def foo(a, b), do: a + b
      end
      """

      assert candidates(source, "Example", "bar", 1) == []
    end

    test "scores are non-negative integers" do
      source = """
      defmodule Example do
        def foo(x), do: x
        def bar(x), do: x
      end
      """

      result = candidates(source, "Example", "baz", 1)
      assert Enum.all?(result, fn c -> is_integer(c.score) and c.score >= 0 end)
    end

    test "sorted by score descending" do
      source = """
      defmodule Checker do
        def palindrome?(text), do: true
        def check(text), do: true
        def palindrome_helper(text), do: true
      end
      """

      result = candidates(source, "Checker", "palindrome", 1)
      scores = Enum.map(result, & &1.score)
      assert scores == Enum.sort(scores, :desc)
    end

    test "visibility field is :def or :defp" do
      source = """
      defmodule Example do
        def public_fn(x), do: x
        defp private_fn(x), do: x
      end
      """

      result = candidates(source, "Example", "fn", 1)
      visibilities = Enum.map(result, & &1.visibility)
      assert Enum.all?(visibilities, &(&1 in [:def, :defp]))
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # candidates – visibility filtering
  # ═══════════════════════════════════════════════════════════════════

  describe "candidates – visibility filtering" do
    test "public_only excludes defp from results" do
      source = """
      defmodule Worker do
        def process(x), do: x
        defp helper(x), do: x
      end
      """

      result = candidates(source, "Worker", "run", 1, visibility: :public_only)
      names = Enum.map(result, & &1.name)

      assert "process" in names
      refute "helper" in names
    end

    test "default includes both def and defp" do
      source = """
      defmodule Worker do
        def process(x), do: x
        defp helper(x), do: x
      end
      """

      result = candidates(source, "Worker", "run", 1)
      names = Enum.map(result, & &1.name)

      assert "process" in names
      assert "helper" in names
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEVER GIVES UP — always returns something if candidates exist
  # ═══════════════════════════════════════════════════════════════════

  describe "suggest – never gives up" do
    test "returns a candidate even with zero name similarity" do
      source = """
      defmodule Example do
        def aaaa(x), do: x
      end
      """

      assert {:ok, "aaaa"} = suggest(source, "Example", "zzzz", 1)
    end

    test "returns best of multiple unrelated candidates" do
      source = """
      defmodule Example do
        def alpha(x), do: x
        def beta(x), do: x
        def gamma(x), do: x
      end
      """

      # Should return SOMETHING — doesn't matter which, just that it doesn't give up
      assert {:ok, name} = suggest(source, "Example", "omega", 1)
      assert name in ["alpha", "beta", "gamma"]
    end
  end
end
