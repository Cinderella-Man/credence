defmodule Credence.Pattern.NoZipThenMapFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoZipThenMap

  # ── Pipeline form ─────────────────────────────────────────────────────

  describe "pipeline – basic zip piped to map" do
    test "simple zip |> map" do
      code = """
      Enum.zip(names, scores)
      |> Enum.map(fn {name, score} -> {name, score * 2} end)
      """

      expected = "Enum.zip_with(names, scores, fn name, score -> {name, score * 2} end)"

      confirm_fix(fix(NoZipThenMap, code), expected)
    end

    test "multiline fn body" do
      code = """
      Enum.zip(keys, values)
      |> Enum.map(fn {k, v} ->
        Map.put(acc, k, v)
      end)
      """

      expected = "Enum.zip_with(keys, values, fn k, v -> Map.put(acc, k, v) end)"

      confirm_fix(fix(NoZipThenMap, code), expected)
    end

    test "zip in longer pipeline" do
      code = """
      list
      |> Enum.filter(&positive?/1)
      |> Enum.zip(other)
      |> Enum.map(fn {a, b} -> a + b end)
      """

      expected = """
      list
      |> Enum.filter(&positive?/1)
      |> Enum.zip_with(other, fn a, b -> a + b end)
      """

      confirm_fix(fix(NoZipThenMap, code), expected)
    end

    test "zip from variable piped to map" do
      code = """
      zipped
      |> Enum.zip(other)
      |> Enum.map(fn {x, y} -> x + y end)
      """

      expected = """
      zipped
      |> Enum.zip_with(other, fn x, y -> x + y end)
      """

      confirm_fix(fix(NoZipThenMap, code), expected)
    end
  end

  # ── Nested form ──────────────────────────────────────────────────────

  describe "nested – map wrapping zip" do
    test "basic nested form" do
      code = """
      Enum.map(Enum.zip(names, scores), fn {name, score} ->
        {name, score * 2}
      end)
      """

      expected = "Enum.zip_with(names, scores, fn name, score -> {name, score * 2} end)"

      confirm_fix(fix(NoZipThenMap, code), expected)
    end

    test "single-line nested form" do
      code = "Enum.map(Enum.zip(a, b), fn {x, y} -> x + y end)"

      expected = "Enum.zip_with(a, b, fn x, y -> x + y end)"

      confirm_fix(fix(NoZipThenMap, code), expected)
    end
  end

  # ── No fix cases ─────────────────────────────────────────────────────

  describe "no fix when guarded" do
    test "guarded fn is not auto-fixed (and not flagged)" do
      code = """
      Enum.zip(names, ages)
      |> Enum.map(fn {name, age} when is_binary(name) -> {name, age} end)
      """

      confirm_fix(fix(NoZipThenMap, code), code)
    end
  end

  describe "no fix when already idiomatic" do
    test "Enum.zip_with is unchanged" do
      code = "Enum.zip_with(names, scores, fn name, score -> {name, score} end)"

      confirm_fix(fix(NoZipThenMap, code), code)
    end
  end

  describe "no fix when fn does not destructure tuple" do
    test "fn with single arg" do
      code = """
      Enum.zip(names, scores)
      |> Enum.map(fn pair -> pair end)
      """

      confirm_fix(fix(NoZipThenMap, code), code)
    end
  end

  describe "no fix for stream inputs" do
    test "preserves the separate zip and map evaluation phases" do
      code =
        "Enum.zip(Stream.map([1, 2], fn x -> Process.put(:zip_state, x); x end), [10, 20]) |> Enum.map(fn {x, y} -> {x, y, Process.get(:zip_state)} end)"

      emitted = fix(NoZipThenMap, code)

      confirm_fix(emitted, code)

      original_fixture = effect_order_fixture(NoZipThenMapOriginalOrder, code)
      emitted_fixture = effect_order_fixture(NoZipThenMapEmittedOrder, emitted)

      assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(original_fixture)
      assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(emitted_fixture)
    end
  end

  describe "no fix for Enum.zip/1 over a list at pipe head" do
    # `Enum.zip([names, scores])` is the real zip/1 (a list of enumerables),
    # not a pipe-elided zip/2 — it must be left untouched.
    test "list-arg zip at pipe head is unchanged" do
      code = """
      Enum.zip([names, scores])
      |> Enum.map(fn {a, b} -> a + b end)
      """

      confirm_fix(fix(NoZipThenMap, code), code)
    end
  end

  defp effect_order_fixture(module, expression) do
    """
    defmodule #{module} do
      Process.delete(:zip_state)
      result = (#{expression})

      unless result == [{1, 10, 2}, {2, 20, 2}],
        do: raise("unexpected evaluation order: \#{inspect(result)}")
    end
    """
  end
end
