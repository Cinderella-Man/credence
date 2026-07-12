defmodule Credence.Syntax.FixPythonSpreadInMapFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixPythonSpreadInMap

  defp analyze(code), do: FixPythonSpreadInMap.analyze(code)
  defp fix(code), do: FixPythonSpreadInMap.fix(code)

  # ═══════════════════════════════════════════════════════════════════
  # BASIC — map with spread at end
  # ═══════════════════════════════════════════════════════════════════

  describe "map with spread at end" do
    test "%{streams: %{}, **state} → Map.merge(%{streams: %{}}, state)" do
      confirm_fix(
        fix("{:ok, %{streams: %{}, **state}}"),
        "{:ok, Map.merge(%{streams: %{}}, state)}"
      )
    end

    test "%{a: 1, b: 2, **opts} → Map.merge(%{a: 1, b: 2}, opts)" do
      confirm_fix(
        fix("%{a: 1, b: 2, **opts}"),
        "Map.merge(%{a: 1, b: 2}, opts)"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # BASIC — bare spread (no explicit keys)
  # ═══════════════════════════════════════════════════════════════════

  describe "bare spread" do
    test "%{**state} → Map.merge(%{}, state)" do
      confirm_fix(
        fix("{:ok, %{**state}}"),
        "{:ok, Map.merge(%{}, state)}"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NESTED MAP
  # ═══════════════════════════════════════════════════════════════════

  describe "nested map" do
    test "%{a: %{b: 1}, **state} → Map.merge(%{a: %{b: 1}}, state)" do
      confirm_fix(
        fix("%{a: %{b: 1}, **state}"),
        "Map.merge(%{a: %{b: 1}}, state)"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # IN FUNCTION BODY
  # ═══════════════════════════════════════════════════════════════════

  describe "in function body" do
    test "one-liner def" do
      confirm_fix(
        fix("def init(state), do: {:ok, %{streams: %{}, **state}}"),
        "def init(state), do: {:ok, Map.merge(%{streams: %{}}, state)}"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # REALISTIC — the actual LLM log case (GenServer init)
  # ═══════════════════════════════════════════════════════════════════

  describe "realistic GenServer init (from log)" do
    test "multi-line module" do
      input = """
      defmodule GenServerInit do
        use GenServer

        def init(state) do
          {:ok, %{streams: %{}, **state}}
        end
      end
      """

      expected = """
      defmodule GenServerInit do
        use GenServer

        def init(state) do
          {:ok, Map.merge(%{streams: %{}}, state)}
        end
      end
      """

      confirm_fix(fix(input), expected)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OPS — plain maps
  # ═══════════════════════════════════════════════════════════════════

  describe "does not touch plain maps" do
    test "map literal unchanged" do
      code = "%{key: value}"

      confirm_fix(fix(code), code)
    end

    test "map in assignment unchanged" do
      code = "x = %{a: 1, b: 2}"

      confirm_fix(fix(code), code)
    end

    test "map update unchanged" do
      code = "%{map | key: new_value}"

      confirm_fix(fix(code), code)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OPS — already correct
  # ═══════════════════════════════════════════════════════════════════

  describe "does not touch already correct code" do
    test "Map.merge(base, extra) unchanged" do
      code = "Map.merge(%{a: 1}, extra)"

      confirm_fix(fix(code), code)
    end

    test "no spread at all" do
      code = """
      defmodule E do
        def run(n), do: n + 1
      end

      """

      confirm_fix(fix(code), code)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OPS — comments
  # ═══════════════════════════════════════════════════════════════════

  describe "does not touch comments" do
    test "comment with spread unchanged" do
      code = "# %{a: 1, **state} is Python syntax"

      confirm_fix(fix(code), code)
    end

    test "indented comment unchanged" do
      code = "  # %{**opts}"

      confirm_fix(fix(code), code)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # PRESERVES SURROUNDING CODE
  # ═══════════════════════════════════════════════════════════════════

  describe "preserves surrounding code" do
    test "only touches lines with **spread" do
      input = """
      defmodule Example do
        def foo(x), do: x + 1
        def bar(s), do: {:ok, %{key: "val", **s}}
        def baz(y), do: y - 1
      end
      """

      expected = """
      defmodule Example do
        def foo(x), do: x + 1
        def bar(s), do: {:ok, Map.merge(%{key: "val"}, s)}
        def baz(y), do: y - 1
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "preserves indentation" do
      confirm_fix(
        fix("    %{a: 1, **opts}"),
        "    Map.merge(%{a: 1}, opts)"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # ROUND-TRIP
  # ═══════════════════════════════════════════════════════════════════

  describe "round-trip" do
    test "fixed code produces zero analyze issues" do
      code = """
      def init(state) do
        {:ok, %{streams: %{}, **state}}
      end
      """

      assert analyze(fix(code)) == []
    end
  end

  describe "fix output is well-formed" do
    test "fixed output parses" do
      assert valid_syntax?(fix("{:ok, %{streams: %{}, **state}}"))
    end
  end
end
