defmodule Credence.Pattern.NoFilterThenCountFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoFilterThenCount

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoFilterThenCount, code, [])
  end

  # ── Pipeline form ──────────────────────────────────────────────────────

  describe "pipeline fix" do
    test "Enum.filter |> length() → Enum.count(enum, pred)" do
      assert fix("numbers |> Enum.filter(fn x -> rem(x, 2) == 0 end) |> length()") ==
               "numbers |> Enum.count(fn x -> rem(x, 2) == 0 end)"
    end

    test "Enum.filter |> Enum.count() → Enum.count(enum, pred)" do
      assert fix("numbers |> Enum.filter(fn x -> rem(x, 2) == 0 end) |> Enum.count()") ==
               "numbers |> Enum.count(fn x -> rem(x, 2) == 0 end)"
    end

    test "with capture syntax" do
      assert fix("items |> Enum.filter(&(&1 > 0)) |> length()") ==
               "items |> Enum.count(&(&1 > 0))"
    end

    test "inside longer pipeline" do
      input = """
      defmodule M do
        def process(data) do
          data
          |> Enum.map(&to_string/1)
          |> Enum.filter(fn s -> String.length(s) > 3 end)
          |> length()
        end
      end
      """

      expected = """
      defmodule M do
        def process(data) do
          data |> Enum.map(&to_string/1) |> Enum.count(fn s -> String.length(s) > 3 end)
        end
      end
      """

      assert fix(input) == expected
    end

    test "2-arg filter piped to length" do
      assert fix("Enum.filter(numbers, &even?/1) |> length()") ==
               "Enum.count(numbers, &even?/1)"
    end
  end

  # ── Nested form ────────────────────────────────────────────────────────

  describe "nested fix" do
    test "length(Enum.filter(enum, pred)) → Enum.count(enum, pred)" do
      assert fix("length(Enum.filter(numbers, fn x -> rem(x, 2) == 0 end))") ==
               "Enum.count(numbers, fn x -> rem(x, 2) == 0 end)"
    end

    test "Enum.count(Enum.filter(enum, pred)) → Enum.count(enum, pred)" do
      assert fix("Enum.count(Enum.filter(numbers, fn x -> rem(x, 2) == 0 end))") ==
               "Enum.count(numbers, fn x -> rem(x, 2) == 0 end)"
    end
  end

  # ── Non-fixable ────────────────────────────────────────────────────────

  describe "does not fix non-matching patterns" do
    test "leaves Enum.filter alone unchanged" do
      code = "numbers |> Enum.filter(fn x -> rem(x, 2) == 0 end)"
      assert fix(code) == code
    end

    test "leaves Enum.count with predicate unchanged" do
      code = "Enum.count(numbers, fn x -> rem(x, 2) == 0 end)"
      assert fix(code) == code
    end

    test "leaves length without filter unchanged" do
      code = "length(numbers)"
      assert fix(code) == code
    end

    test "leaves Enum.filter |> Enum.map unchanged" do
      code = "numbers |> Enum.filter(fn x -> rem(x, 2) == 0 end) |> Enum.map(fn x -> x * x end)"
      assert fix(code) == code
    end
  end
end
