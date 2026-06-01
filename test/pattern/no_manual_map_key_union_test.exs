defmodule Credence.Pattern.NoManualMapKeyUnionTest do
  use ExUnit.Case

  alias Credence.Pattern.NoManualMapKeyUnion

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoManualMapKeyUnion.check(ast, [])
  end

  defp apply_fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoManualMapKeyUnion, code)
  end

  # ═══════════════════════════════════════════════════════════════════
  # SHOULD fire
  # ═══════════════════════════════════════════════════════════════════

  describe "check: flags Map.keys ++ Map.keys |> Enum.uniq" do
    test "pipe form" do
      code = """
      defmodule TestMod do
        def all_keys(m1, m2) do
          (Map.keys(m1) ++ Map.keys(m2))
          |> Enum.uniq()
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_manual_map_key_union
    end

    test "nested form" do
      code = """
      defmodule TestMod do
        def all_keys(m1, m2) do
          Enum.uniq(Map.keys(m1) ++ Map.keys(m2))
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "inside a pipeline with further processing" do
      code = """
      defmodule TestMod do
        def all_chars(freq1, freq2) do
          (Map.keys(freq1) ++ Map.keys(freq2))
          |> Enum.uniq()
          |> Enum.sort()
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # should NOT fire
  # ═══════════════════════════════════════════════════════════════════

  describe "check: does not flag" do
    test "Map.keys on a single map" do
      code = """
      defmodule TestMod do
        def keys(m), do: Map.keys(m)
      end
      """

      assert check(code) == []
    end

    test "Map.keys ++ Map.keys without Enum.uniq" do
      code = """
      defmodule TestMod do
        def concat_keys(m1, m2) do
          Map.keys(m1) ++ Map.keys(m2)
        end
      end
      """

      assert check(code) == []
    end

    test "Map.merge already used" do
      code = """
      defmodule TestMod do
        def merged_keys(m1, m2) do
          Map.merge(m1, m2) |> Map.keys()
        end
      end
      """

      assert check(code) == []
    end

    test "Enum.uniq on a single Map.keys" do
      code = """
      defmodule TestMod do
        def unique_keys(m) do
          Enum.uniq(Map.keys(m))
        end
      end
      """

      assert check(code) == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Auto-fix
  # ═══════════════════════════════════════════════════════════════════

  describe "fix" do
    test "pipe form → Map.merge |> Map.keys" do
      before = """
      defmodule TestMod do
        def all_keys(m1, m2) do
          (Map.keys(m1) ++ Map.keys(m2))
          |> Enum.uniq()
        end
      end
      """

      after_ = apply_fix(before)
      assert after_ =~ "Map.merge"
      assert after_ =~ "Map.keys"
      refute after_ =~ "Enum.uniq"
      refute after_ =~ "++"
    end

    test "nested form → Map.merge |> Map.keys" do
      before = """
      defmodule TestMod do
        def all_keys(m1, m2) do
          Enum.uniq(Map.keys(m1) ++ Map.keys(m2))
        end
      end
      """

      after_ = apply_fix(before)
      assert after_ =~ "Map.merge"
      assert after_ =~ "Map.keys"
      refute after_ =~ "Enum.uniq"
      refute after_ =~ "++"
    end

    test "preserves variable names" do
      before = """
      defmodule TestMod do
        def check(word1, word2) do
          freq1 = build_freq(word1)
          freq2 = build_freq(word2)

          all_chars =
            (Map.keys(freq1) ++ Map.keys(freq2))
            |> Enum.uniq()

          all_chars
          |> Enum.all?(fn char -> true end)
        end
      end
      """

      after_ = apply_fix(before)
      assert after_ =~ "Map.merge(freq1, freq2)"
      assert after_ =~ "Map.keys()"
    end
  end
end
