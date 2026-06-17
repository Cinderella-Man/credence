defmodule Credence.Pattern.NoMapKeysOrValuesForIterationCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoMapKeysOrValuesForIteration

  describe "flags nested form" do
    test "Enum.all?(Map.values(m), ...)" do
      assert [%Issue{rule: :no_map_keys_or_values_for_iteration}] =
               check(
                 NoMapKeysOrValuesForIteration,
                 "Enum.all?(Map.values(degrees), fn v -> v == 0 end)"
               )
    end

    test "does not flag Enum.filter (order-dependent — diverges for > 32-key maps)" do
      assert check(NoMapKeysOrValuesForIteration, "Enum.filter(Map.values(m), fn v -> v > 0 end)") ==
               []
    end

    test "Enum.count(Map.values(m))" do
      assert [%Issue{rule: :no_map_keys_or_values_for_iteration}] =
               check(NoMapKeysOrValuesForIteration, "Enum.count(Map.values(m))")
    end

    test "multiple violations in same module" do
      code = """
      defmodule Example do
        def f(m), do: Enum.all?(Map.values(m), fn v -> v == 0 end)
        def g(m), do: Enum.count(Map.keys(m))
      end
      """

      assert length(check(NoMapKeysOrValuesForIteration, code)) == 2
    end
  end

  describe "does not flag order-dependent pipe form" do
    test "Map.keys(m) |> Enum.map(&to_string/1) (order-dependent — diverges for > 32-key maps)" do
      assert check(NoMapKeysOrValuesForIteration, "Map.keys(map) |> Enum.map(&to_string/1)") == []
    end
  end

  describe "flags triple-pipe form" do
    test "map |> Map.values() |> Enum.count()" do
      assert [%Issue{rule: :no_map_keys_or_values_for_iteration}] =
               check(NoMapKeysOrValuesForIteration, "map |> Map.values() |> Enum.count()")
    end
  end

  describe "does NOT flag" do
    test "iterating map directly" do
      assert check(NoMapKeysOrValuesForIteration, "Enum.all?(m, fn {_, v} -> v == 0 end)") == []
    end

    test "Map.values used without Enum" do
      assert check(NoMapKeysOrValuesForIteration, "Map.values(m)") == []
    end

    test "Map.keys in non-Enum context" do
      assert check(NoMapKeysOrValuesForIteration, "length(Map.keys(m))") == []
    end

    test "unfixable Enum function" do
      assert check(NoMapKeysOrValuesForIteration, "Enum.chunk_every(Map.values(m), 2)") == []
    end

    test "Map.values |> Enum.max — already idiomatic" do
      assert check(NoMapKeysOrValuesForIteration, "Map.values(map) |> Enum.max()") == []
    end

    test "Map.values |> Enum.min — already idiomatic" do
      assert check(NoMapKeysOrValuesForIteration, "Map.values(map) |> Enum.min()") == []
    end

    test "Enum.max(Map.values(m)) — already idiomatic" do
      assert check(NoMapKeysOrValuesForIteration, "Enum.max(Map.values(m))") == []
    end

    test "Map.keys |> Enum.max — already idiomatic" do
      assert check(NoMapKeysOrValuesForIteration, "Map.keys(map) |> Enum.max()") == []
    end

    test "Enum.sum(Map.values(m)) — already idiomatic" do
      assert check(NoMapKeysOrValuesForIteration, "Enum.sum(Map.values(m))") == []
    end

    test "Map.values |> Enum.sum() — already idiomatic" do
      assert check(NoMapKeysOrValuesForIteration, "Map.values(map) |> Enum.sum()") == []
    end

    test "Enum.product(Map.keys(m)) — already idiomatic" do
      assert check(NoMapKeysOrValuesForIteration, "Enum.product(Map.keys(m))") == []
    end

    test "map |> Map.values() |> Enum.sum() — already idiomatic" do
      assert check(NoMapKeysOrValuesForIteration, "map |> Map.values() |> Enum.sum()") == []
    end
  end

  describe "metadata" do
    test "meta.line is set" do
      [issue] =
        check(NoMapKeysOrValuesForIteration, "Enum.all?(Map.values(m), fn v -> v == 0 end)")

      assert issue.meta.line != nil
    end

    test "message references both Map and Enum functions" do
      [issue] =
        check(NoMapKeysOrValuesForIteration, "Enum.all?(Map.values(m), fn v -> v == 0 end)")

      assert issue.message =~ "Map.values"
      assert issue.message =~ "Enum.all?"
    end
  end

  # Safe-core boundary: a `&(...)` capture whose body ends in a CALL has an
  # unreliable Sourceror range (the patch would orphan the capture's `)`), so
  # the rule must NOT fire — while range-safe captures still do.
  describe "skips a call-ending &(...) capture (range-unreliable)" do
    test "&(not blank?(&1)) — body ends in a call" do
      assert check(NoMapKeysOrValuesForIteration, "Enum.all?(Map.keys(m), &(not blank?(&1)))") ==
               []
    end

    test "&(String.upcase(&1)) — body ends in a remote call" do
      assert check(NoMapKeysOrValuesForIteration, "Enum.all?(Map.keys(m), &(String.upcase(&1)))") ==
               []
    end

    test "still flags a literal-ending capture &(&1 > 0)" do
      assert [%Issue{}] = check(NoMapKeysOrValuesForIteration, "Enum.all?(Map.keys(m), &(&1 > 0))")
    end
  end
end
