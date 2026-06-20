defmodule Credence.Pattern.NoMapKeysOrValuesForIterationFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoMapKeysOrValuesForIteration, as: R

  # The rule rewrites ONLY the order-independent terminals — all?, any?, count,
  # empty?, frequencies, frequencies_by — because `Map.keys/values` iterate in a
  # different order than a direct `Enum`-over-map traversal for maps with > 32
  # keys. Any order-dependent op (map/filter/find/at/take/join/reduce/…) is left
  # untouched: the check does not flag it and the fix does not rewrite it (the two
  # share the same `fixable?/2` scope gate).

  # ═══════════════════════════════════════════════════════════════
  # fixable ops — nested form
  # ═══════════════════════════════════════════════════════════════

  describe "fixable ops — nested, callback wrapped to the {k, v} pair" do
    test "Enum.all? with Map.values binds the value slot" do
      confirm_fix(
        fix(R, "Enum.all?(Map.values(degrees), fn v -> v == 0 end)"),
        "Enum.all?(degrees, fn {_k, v} -> v == 0 end)"
      )
    end

    test "Enum.any? with Map.keys binds the key slot" do
      confirm_fix(
        fix(R, "Enum.any?(Map.keys(m), fn k -> k > 0 end)"),
        "Enum.any?(m, fn {k, _v} -> k > 0 end)"
      )
    end

    test "Enum.count with predicate" do
      confirm_fix(
        fix(R, "Enum.count(Map.values(m), fn v -> v > 0 end)"),
        "Enum.count(m, fn {_k, v} -> v > 0 end)"
      )
    end

    test "Enum.frequencies_by with Map.values" do
      confirm_fix(
        fix(R, "Enum.frequencies_by(Map.values(m), fn v -> rem(v, 2) end)"),
        "Enum.frequencies_by(m, fn {_k, v} -> rem(v, 2) end)"
      )
    end

    test "lambda with a guard is preserved" do
      confirm_fix(
        fix(R, "Enum.all?(Map.values(m), fn v when is_integer(v) -> true end)"),
        "Enum.all?(m, fn {_k, v} when is_integer(v) -> true end)"
      )
    end

    test "&func/1 capture is expanded and wrapped" do
      confirm_fix(
        fix(R, "Enum.all?(Map.keys(m), &is_atom/1)"),
        "Enum.all?(m, fn {x, _v} -> is_atom(x) end)"
      )
    end

    test "complex capture &(&1 > 0) is converted and wrapped" do
      confirm_fix(
        fix(R, "Enum.all?(Map.values(m), &(&1 > 0))"),
        "Enum.all?(m, fn {_k, x} -> x > 0 end)"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # fixable ops — callback-less terminals (count / empty? / frequencies)
  # ═══════════════════════════════════════════════════════════════

  describe "fixable ops — no callback" do
    test "Enum.count(Map.values(m))" do
      confirm_fix(fix(R, "Enum.count(Map.values(m))"), "Enum.count(m)")
    end

    test "Enum.count(Map.keys(m))" do
      confirm_fix(fix(R, "Enum.count(Map.keys(m))"), "Enum.count(m)")
    end

    test "Enum.empty?(Map.values(m))" do
      confirm_fix(fix(R, "Enum.empty?(Map.values(m))"), "Enum.empty?(m)")
    end

    test "Enum.empty?(Map.keys(m))" do
      confirm_fix(fix(R, "Enum.empty?(Map.keys(m))"), "Enum.empty?(m)")
    end

    test "Enum.frequencies(Map.values(m)) → frequencies_by extracting the value" do
      confirm_fix(
        fix(R, "Enum.frequencies(Map.values(m))"),
        "Enum.frequencies_by(m, fn {_, v} -> v end)"
      )
    end

    test "Enum.frequencies(Map.keys(m)) → frequencies_by extracting the key" do
      confirm_fix(
        fix(R, "Enum.frequencies(Map.keys(m))"),
        "Enum.frequencies_by(m, fn {k, _} -> k end)"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # fixable ops — pipe + triple-pipe forms
  # ═══════════════════════════════════════════════════════════════

  describe "fixable ops — pipe forms" do
    test "Map.values |> Enum.all?(fn)" do
      confirm_fix(
        fix(R, "Map.values(m) |> Enum.all?(fn v -> v == 0 end)"),
        "Enum.all?(m, fn {_k, v} -> v == 0 end)"
      )
    end

    test "Map.values |> Enum.count()" do
      confirm_fix(fix(R, "Map.values(map) |> Enum.count()"), "Enum.count(map)")
    end

    test "Map.values |> Enum.frequencies()" do
      confirm_fix(
        fix(R, "Map.values(m) |> Enum.frequencies()"),
        "Enum.frequencies_by(m, fn {_, v} -> v end)"
      )
    end

    test "triple pipe: map |> Map.keys() |> Enum.count()" do
      confirm_fix(fix(R, "map |> Map.keys() |> Enum.count()"), "Enum.count(map)")
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # order-dependent ops — NEVER rewritten (would reorder the result for
  # maps with > 32 keys). Both check and fix leave them alone.
  # ═══════════════════════════════════════════════════════════════

  describe "order-dependent ops are not rewritten" do
    for {label, code} <- [
          {"map", "Map.values(m) |> Enum.map(fn v -> v + 1 end)"},
          {"filter", "Map.values(m) |> Enum.filter(fn v -> v > 0 end)"},
          {"reject capture", "fields |> Map.keys() |> Enum.reject(&(&1 in valid))"},
          {"reduce", "Enum.reduce(Map.values(m), 0, fn v, acc -> v + acc end)"},
          {"find", "Enum.find(Map.values(m), fn v -> v > 0 end)"},
          {"at", "Map.values(m) |> Enum.at(0)"},
          {"take", "Map.values(m) |> Enum.take(2)"},
          {"join", "Map.keys(m) |> Enum.join(\",\")"},
          {"uniq", "Map.values(m) |> Enum.uniq()"},
          {"max_by", "Enum.max_by(Map.values(m), fn v -> v end)"},
          {"each", "Enum.each(Map.values(m), fn v -> IO.puts(v) end)"},
          {"flat_map", "Enum.flat_map(Map.values(m), fn v -> [v] end)"},
          {"group_by", "Enum.group_by(Map.values(m), fn v -> rem(v, 2) end)"},
          {"sort", "Map.values(m) |> Enum.sort()"}
        ] do
      test "leaves Enum.#{label} untouched" do
        confirm_fix(fix(R, unquote(code)), unquote(code))
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # already-idiomatic — no fix
  # ═══════════════════════════════════════════════════════════════

  describe "already-idiomatic terminals are not rewritten" do
    for code <- [
          "Enum.sum(Map.values(m))",
          "Enum.product(Map.values(m))",
          "Enum.max(Map.values(m))",
          "Enum.min(Map.values(m))",
          "Map.values(m) |> Enum.sum()"
        ] do
      test "no fix: #{code}" do
        confirm_fix(fix(R, unquote(code)), unquote(code))
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # round-trip: a fixed result is itself clean
  # ═══════════════════════════════════════════════════════════════

  describe "round-trip" do
    for code <- [
          "Enum.all?(Map.values(m), fn v -> v == 0 end)",
          "Map.values(m) |> Enum.count()",
          "Enum.frequencies(Map.keys(m))"
        ] do
      test "fixed code re-checks clean: #{code}" do
        assert clean?(R, fix(R, unquote(code)))
      end
    end
  end
end
