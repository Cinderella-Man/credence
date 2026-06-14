defmodule Credence.Pattern.NoMapPutGetIncrementFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoMapPutGetIncrement

  describe "rewrites the safe core" do
    test "bare Map.put/Map.get + 1" do
      code = "Map.put(freqs, char, Map.get(freqs, char, 0) + 1)"

      expected = "Map.update(freqs, char, 1, fn x -> x + 1 end)"

      confirm_fix(fix(NoMapPutGetIncrement, code), expected)
    end

    test "piped form keeps the pipe" do
      code = "freqs |> Map.put(key, Map.get(freqs, key, 0) + 1)"

      expected = "freqs |> Map.update(key, 1, fn x -> x + 1 end)"

      confirm_fix(fix(NoMapPutGetIncrement, code), expected)
    end

    test "integer increment other than 1 carries through to default and fun" do
      code = "Map.put(m, k, Map.get(m, k, 0) + 5)"

      expected = "Map.update(m, k, 5, fn x -> x + 5 end)"

      confirm_fix(fix(NoMapPutGetIncrement, code), expected)
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

      expected = """
      defmodule M do
        def inc(freqs, char) do
          updated = Map.update(freqs, char, 1, fn x -> x + 1 end)
          {:ok, updated}
        end
      end
      """

      confirm_fix(fix(NoMapPutGetIncrement, code), expected)
    end

    test "rewrites multiple instances" do
      code = """
      defmodule Freq do
        def update(a, b, fa, fb) do
          fa = Map.put(fa, a, Map.get(fa, a, 0) + 1)
          fb = Map.put(fb, b, Map.get(fb, b, 0) + 1)
          {fa, fb}
        end
      end
      """

      expected = """
      defmodule Freq do
        def update(a, b, fa, fb) do
          fa = Map.update(fa, a, 1, fn x -> x + 1 end)
          fb = Map.update(fb, b, 1, fn x -> x + 1 end)
          {fa, fb}
        end
      end
      """

      confirm_fix(fix(NoMapPutGetIncrement, code), expected)
    end

    test "round-trip: fixed code is no longer flagged" do
      code = "Map.put(freqs, char, Map.get(freqs, char, 0) + 1)"

      fixed = fix(NoMapPutGetIncrement, code)
      assert clean?(NoMapPutGetIncrement, fixed)
    end
  end

  describe "leaves unsafe / unrelated code untouched" do
    test "already-idiomatic Map.update" do
      code = "Map.update(freqs, char, 1, &(&1 + 1))"

      confirm_fix(fix(NoMapPutGetIncrement, code), code)
    end

    test "different literal keys are not rewritten" do
      code = "Map.put(m, :a, Map.get(m, :b, 0) + 1)"

      confirm_fix(fix(NoMapPutGetIncrement, code), code)
    end

    test "variable increment is not rewritten" do
      code = "Map.put(m, k, Map.get(m, k, 0) + n)"

      confirm_fix(fix(NoMapPutGetIncrement, code), code)
    end

    test "float increment is not rewritten" do
      code = "Map.put(m, k, Map.get(m, k, 0) + 1.0)"

      confirm_fix(fix(NoMapPutGetIncrement, code), code)
    end

    test "float default is not rewritten" do
      code = "Map.put(m, k, Map.get(m, k, 0.0) + 1)"

      confirm_fix(fix(NoMapPutGetIncrement, code), code)
    end
  end
end
