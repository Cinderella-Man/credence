defmodule Credence.Pattern.AvoidRebindingParameterFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.AvoidRebindingParameter

  # ═══════════════════════════════════════════════════════════════════
  # FIXABLE — parameter rebinding → distinct variable name
  # ═══════════════════════════════════════════════════════════════════

  describe "rewrites parameter rebinding to distinct name" do
    test "simple rebinding of k" do
      input = """
      defmodule Example do
        def compute(n, k) do
          k = min(k, n - k)
          k + 1
        end
      end
      """

      expected = """
      defmodule Example do
        def compute(n, k) do
          k_opt = min(k, n - k)
          k_opt + 1
        end
      end
      """

      assert fix(AvoidRebindingParameter, input) == expected
    end

    test "rebinding in defp" do
      input = """
      defmodule Example do
        defp helper(x, y) do
          y = x + y
          y * 2
        end
      end
      """

      expected = """
      defmodule Example do
        defp helper(x, y) do
          y_opt = x + y
          y_opt * 2
        end
      end
      """

      assert fix(AvoidRebindingParameter, input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NOT FIXABLE — left exactly as-is (no rebinding detected)
  # ═══════════════════════════════════════════════════════════════════

  describe "leaves clean code untouched" do
    test "parameters used but not rebound" do
      code = """
      defmodule Example do
        def compute(n, k) do
          min(k, n - k) + 1
        end
      end
      """

      assert fix(AvoidRebindingParameter, code) == code
    end

    test "local variable assignment that is not a parameter" do
      code = """
      defmodule Example do
        def compute(n, k) do
          result = min(k, n - k)
          result + 1
        end
      end
      """

      assert fix(AvoidRebindingParameter, code) == code
    end
  end
end
