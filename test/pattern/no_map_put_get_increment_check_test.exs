defmodule Credence.Pattern.NoMapPutGetIncrementCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoMapPutGetIncrement

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoMapPutGetIncrement.check(ast, [])
  end

  describe "fires (safe core)" do
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

    test "detects the recursive binary frequency-count shape" do
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

    test "detects piped form" do
      code = """
      freqs |> Map.put(key, Map.get(freqs, key, 0) + 1)
      """

      assert length(check(code)) == 1
    end

    test "detects an integer increment other than 1" do
      code = """
      Map.put(m, k, Map.get(m, k, 0) + 5)
      """

      assert length(check(code)) == 1
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

      assert length(check(code)) == 2
    end
  end

  describe "does not fire" do
    test "different map variable in get" do
      code = """
      Map.put(freqs, char, Map.get(other_map, char, 0) + 1)
      """

      assert check(code) == []
    end

    test "non-zero default" do
      code = """
      Map.put(freqs, char, Map.get(freqs, char, 10) + 1)
      """

      assert check(code) == []
    end

    test "non-increment expression" do
      code = """
      Map.put(freqs, char, Map.get(freqs, char, 0) * 2)
      """

      assert check(code) == []
    end

    test "no Map.get at all" do
      code = """
      Map.put(freqs, char, some_value + 1)
      """

      assert check(code) == []
    end

    test "already idiomatic Map.update" do
      code = """
      Map.update(freqs, char, 1, &(&1 + 1))
      """

      assert check(code) == []
    end

    # --- deliberately-dropped unsafe cases (locked in as "no issue") ---

    test "two DIFFERENT literal keys must not falsely match" do
      # Reads :b but writes :a — a naive rewrite to Map.update(m, :a, ...) is wrong.
      code = """
      Map.put(m, :a, Map.get(m, :b, 0) + 1)
      """

      assert check(code) == []
    end

    test "literal keys are out of the safe core (even when equal)" do
      code = """
      Map.put(counts, "a", Map.get(counts, "a", 0) + 1)
      """

      assert check(code) == []
    end

    test "non-integer (variable) increment is not safe" do
      # Map.update's 4th arg must be a function; a bare variable would not work.
      code = """
      Map.put(m, k, Map.get(m, k, 0) + n)
      """

      assert check(code) == []
    end

    test "float increment is not safe" do
      code = """
      Map.put(m, k, Map.get(m, k, 0) + 1.0)
      """

      assert check(code) == []
    end

    test "float default 0.0 is not the integer 0 (type-changing)" do
      # `0.0 + 1` is the float 1.0; the fix would emit integer default 1.
      code = """
      Map.put(m, k, Map.get(m, k, 0.0) + 1)
      """

      assert check(code) == []
    end

    test "non-variable (call) map is out of the safe core" do
      code = """
      Map.put(build(), k, Map.get(build(), k, 0) + 1)
      """

      assert check(code) == []
    end
  end
end
