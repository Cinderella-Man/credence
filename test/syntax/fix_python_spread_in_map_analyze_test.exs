defmodule Credence.Syntax.FixPythonSpreadInMapAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixPythonSpreadInMap

  defp analyze(code), do: FixPythonSpreadInMap.analyze(code)

  # ═══════════════════════════════════════════════════════════════════
  # FLAGS — map with spread at end
  # ═══════════════════════════════════════════════════════════════════

  describe "flags map with spread at end" do
    test "%{streams: %{}, **state}" do
      assert [%Issue{rule: :fix_python_spread_in_map}] =
               analyze("%{streams: %{}, **state}")
    end

    test "%{a: 1, b: 2, **opts}" do
      assert [%Issue{}] =
               analyze("%{a: 1, b: 2, **opts}")
    end

    test "in tuple context" do
      assert [%Issue{}] =
               analyze("{:ok, %{streams: %{}, **state}}")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FLAGS — bare spread (no explicit keys)
  # ═══════════════════════════════════════════════════════════════════

  describe "flags bare spread" do
    test "%{**opts}" do
      assert [%Issue{}] =
               analyze("%{**opts}")
    end

    test "{:ok, %{**state}}" do
      assert [%Issue{}] =
               analyze("{:ok, %{**state}}")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FLAGS — in function body
  # ═══════════════════════════════════════════════════════════════════

  describe "flags in function body" do
    test "one-liner def" do
      assert [%Issue{}] =
               analyze("def init(state), do: {:ok, %{streams: %{}, **state}}")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FLAGS — multiple lines
  # ═══════════════════════════════════════════════════════════════════

  describe "flags multiple lines" do
    test "each spread line gets its own issue" do
      code = """
      def init(state) do
        {:ok, %{streams: %{}, **state}}
      end

      def connect(opts) do
        %{host: "localhost", **opts}
      end
      """

      assert length(analyze(code)) == 2
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DOES NOT FLAG — plain map literals
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag plain map literals" do
    test "%{key: value}" do
      assert analyze("%{key: value}") == []
    end

    test "x = %{a: 1, b: 2}" do
      assert analyze("x = %{a: 1, b: 2}") == []
    end

    test "%{map | key: new_value}" do
      assert analyze("%{map | key: new_value}") == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DOES NOT FLAG — Map.merge (already correct)
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag Map.merge" do
    test "Map.merge(base, extra)" do
      assert analyze("Map.merge(%{a: 1}, extra)") == []
    end

    test "Map.merge with nested map" do
      assert analyze("Map.merge(%{streams: %{}}, state)") == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DOES NOT FLAG — comments
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag comments" do
    test "# %{a: 1, **state}" do
      assert analyze("# %{a: 1, **state}") == []
    end

    test "  # spread syntax" do
      assert analyze("  # %{**opts}") == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DOES NOT FLAG — no spread at all
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag clean code" do
    test "plain function call" do
      assert analyze("Enum.map(list, &fun/1)") == []
    end

    test "assignment" do
      assert analyze("x = a + b * c") == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # METADATA
  # ═══════════════════════════════════════════════════════════════════

  describe "metadata" do
    test "reports correct line number" do
      code = """
      x = 1
      {:ok, %{streams: %{}, **state}}
      y = 3
      """

      [issue] = analyze(code)
      assert issue.meta.line == 2
    end
  end
end
