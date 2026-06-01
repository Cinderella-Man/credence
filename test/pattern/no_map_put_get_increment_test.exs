defmodule Credence.Pattern.NoMapPutGetIncrementTest do
  use ExUnit.Case

  alias Credence.Pattern.NoMapPutGetIncrement

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoMapPutGetIncrement.check(ast, [])
  end

  defp fix(code),
    do: Credence.RuleHelpers.apply_rule_fix(NoMapPutGetIncrement, code, [])

  describe "check" do
    test "detects Map.put/Map.get + 1 pattern" do
      code = """
      defmodule Freq do
        def count(char, freqs) do
          Map.put(freqs, char, Map.get(freqs, char, 0) + 1)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_map_put_get_increment
      assert hd(issues).message =~ "Map.update"
    end

    test "detects nested in recursive function" do
      code = """
      defmodule Freq do
        defp count_frequencies(<<>>), do: %{}
        defp count_frequencies(<<char, rest::binary>>) do
          freqs = count_frequencies(rest)
          Map.put(freqs, char, Map.get(freqs, char, 0) + 1)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_map_put_get_increment
    end

    test "detects piped form" do
      code = """
      freqs |> Map.put(key, Map.get(freqs, key, 0) + 1)
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "does not fire on Map.put with unrelated Map.get" do
      code = """
      Map.put(freqs, char, Map.get(other_map, char, 0) + 1)
      """

      assert check(code) == []
    end

    test "does not fire on Map.put with non-zero default" do
      code = """
      Map.put(freqs, char, Map.get(freqs, char, 10) + 1)
      """

      assert check(code) == []
    end

    test "does not fire on Map.put with non-increment expression" do
      code = """
      Map.put(freqs, char, Map.get(freqs, char, 0) * 2)
      """

      assert check(code) == []
    end

    test "does not fire on Map.put without Map.get" do
      code = """
      Map.put(freqs, char, some_value + 1)
      """

      assert check(code) == []
    end

    test "does not fire on Map.update (already idiomatic)" do
      code = """
      Map.update(freqs, char, 1, &(&1 + 1))
      """

      assert check(code) == []
    end

    test "detects the exact pattern from row 86863 (recursive binary frequency count)" do
      code = """
      defmodule Solution do
        defp count_frequencies(<<>>), do: %{}
        defp count_frequencies(<<char, rest::binary>>) do
          freqs = count_frequencies(rest)
          Map.put(freqs, char, Map.get(freqs, char, 0) + 1)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_map_put_get_increment
    end

    test "detects multiple instances" do
      code = """
      defmodule Freq do
        def update(a, b, fa, fb) do
          fa = Map.put(fa, a, Map.get(fa, a, 0) + 1)
          fb = Map.put(fb, b, Map.get(fb, b, 0) + 1)
          {fa, fb}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end
  end

  describe "fix" do
    test "replaces Map.put/Map.get + 1 with Map.update" do
      code = """
      Map.put(freqs, char, Map.get(freqs, char, 0) + 1)
      """

      result = fix(code)
      assert result =~ "Map.update"
      assert result =~ "fn x -> x + 1 end"
      refute result =~ "Map.put"
      refute result =~ "Map.get"
    end

    test "preserves variable names" do
      code = """
      Map.put(counts, item, Map.get(counts, item, 0) + 1)
      """

      result = fix(code)
      assert result =~ "Map.update(counts, item"
    end

    test "round-trip: fixed code produces no issues" do
      code = """
      Map.put(freqs, char, Map.get(freqs, char, 0) + 1)
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoMapPutGetIncrement.check(ast, []) == []
    end

    test "does not modify Map.update (already correct)" do
      code = """
      Map.update(freqs, char, 1, &(&1 + 1))
      """

      result = fix(code)
      assert result =~ "Map.update"
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def inc(freqs, char) do
          updated = Map.put(freqs, char, Map.get(freqs, char, 0) + 1)
          {:ok, updated}
        end
      end
      """

      result = fix(code)
      assert result =~ "Map.update"
      assert result =~ "{:ok, updated}"
    end
  end
end
