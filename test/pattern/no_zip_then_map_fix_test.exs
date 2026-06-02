defmodule Credence.Pattern.NoZipThenMapFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoZipThenMap

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoZipThenMap, code, [])
  end

  # ── Pipeline form ─────────────────────────────────────────────────────

  describe "pipeline – basic zip piped to map" do
    test "simple zip |> map" do
      result = fix("Enum.zip(names, scores)\n|> Enum.map(fn {name, score} -> {name, score * 2} end)\n")
      assert result =~ "Enum.zip_with(names, scores, fn name, score -> {name, score * 2} end)"
    end

    test "multiline fn body" do
      result = fix("Enum.zip(keys, values)\n|> Enum.map(fn {k, v} ->\n  Map.put(acc, k, v)\nend)\n")
      assert result =~ "Enum.zip_with(keys, values, fn k, v -> Map.put(acc, k, v) end)"
    end

    test "zip in longer pipeline" do
      result = fix("list\n|> Enum.filter(&positive?/1)\n|> Enum.zip(other)\n|> Enum.map(fn {a, b} -> a + b end)\n")
      assert result =~ "list\n|> Enum.filter(&positive?/1)\n|> Enum.zip_with(other, fn a, b -> a + b end)"
    end

    test "zip from variable piped to map" do
      result = fix("zipped\n|> Enum.zip(other)\n|> Enum.map(fn {x, y} -> x + y end)\n")
      assert result =~ "zipped\n|> Enum.zip_with(other, fn x, y -> x + y end)"
    end
  end

  # ── Nested form ──────────────────────────────────────────────────────

  describe "nested – map wrapping zip" do
    test "basic nested form" do
      result = fix("Enum.map(Enum.zip(names, scores), fn {name, score} ->\n  {name, score * 2}\nend)\n")
      assert result =~ "Enum.zip_with(names, scores, fn name, score -> {name, score * 2} end)"
    end

    test "single-line nested form" do
      result = fix("Enum.map(Enum.zip(a, b), fn {x, y} -> x + y end)\n")
      assert result =~ "Enum.zip_with(a, b, fn x, y -> x + y end)"
    end
  end

  # ── No fix cases ─────────────────────────────────────────────────────

  describe "no fix when guarded" do
    test "guarded fn is not auto-fixed" do
      code = "Enum.zip(names, ages)\n|> Enum.map(fn {name, age} when is_binary(name) -> {name, age} end)\n"
      assert fix(code) == code
    end
  end

  describe "no fix when already idiomatic" do
    test "Enum.zip_with is unchanged" do
      code = "Enum.zip_with(names, scores, fn name, score -> {name, score} end)\n"
      assert fix(code) == code
    end
  end

  describe "no fix when fn does not destructure tuple" do
    test "fn with single arg" do
      code = "Enum.zip(names, scores)\n|> Enum.map(fn pair -> pair end)\n"
      assert fix(code) == code
    end
  end
end
